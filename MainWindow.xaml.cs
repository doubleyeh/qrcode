using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using QRCoder;

namespace QrCodeApp
{
    public partial class MainWindow : Window
    {
        const int HOTKEY_ID = 1;
        const int WM_HOTKEY = 0x0312;
        const uint MOD_ALT = 0x1, MOD_SHIFT = 0x4, MOD_NOREPEAT = 0x4000;
        const uint VK_Q = 0x51;

        IntPtr hwnd;
        System.Windows.Forms.NotifyIcon tray;
        bool quitting, busy;

        public MainWindow()
        {
            InitializeComponent();
            SourceInitialized += OnSourceInitialized;

            tray = new System.Windows.Forms.NotifyIcon
            {
                Icon = System.Drawing.SystemIcons.Application,
                Text = "二维码生成器",
                Visible = true
            };
            tray.DoubleClick += (s, e) => ShowMain();
            var menu = new System.Windows.Forms.ContextMenuStrip();
            menu.Items.Add("显示", null, (s, e) => ShowMain());
            menu.Items.Add("退出", null, (s, e) => Quit());
            tray.ContextMenuStrip = menu;
        }

        void OnSourceInitialized(object sender, EventArgs e)
        {
            hwnd = new WindowInteropHelper(this).Handle;
            HwndSource.FromHwnd(hwnd).AddHook(WndProc);
            if (!Native.RegisterHotKey(hwnd, HOTKEY_ID, MOD_SHIFT | MOD_ALT | MOD_NOREPEAT, VK_Q))
                Status.Text = "快捷键 Shift+Alt+Q 注册失败（可能被占用）";
        }

        IntPtr WndProc(IntPtr h, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == WM_HOTKEY && wParam.ToInt32() == HOTKEY_ID)
            {
                handled = true;
                var _ = CaptureAsync();
            }
            return IntPtr.Zero;
        }

        async Task CaptureAsync()
        {
            if (busy) return;
            busy = true;
            try
            {
                // 插入无效按键，避免松开 Alt 时目标程序激活菜单栏
                Native.Send(Native.Key(0xFF, false), Native.Key(0xFF, true));

                // 等用户松开 Shift/Alt/Q，否则目标程序收到的是 Ctrl+Shift+Alt+C
                for (int i = 0; i < 100 && (Native.IsDown(0x10) || Native.IsDown(0x12) || Native.IsDown(0x51)); i++)
                    await Task.Delay(10);

                uint before = Native.GetClipboardSequenceNumber();
                Native.Send(
                    Native.Key(0x11, false), Native.Key(0x43, false),
                    Native.Key(0x43, true), Native.Key(0x11, true));

                string text = null;
                for (int i = 0; i < 20; i++)
                {
                    await Task.Delay(25);
                    if (Native.GetClipboardSequenceNumber() != before)
                    {
                        text = ReadClipboard();
                        break;
                    }
                }

                ShowMain();
                if (text == null) Status.Text = "未获取到选中文本";
                else Input.Text = text;
            }
            finally { busy = false; }
        }

        static string ReadClipboard()
        {
            for (int i = 0; i < 5; i++)
            {
                try
                {
                    return Clipboard.ContainsText() ? Clipboard.GetText(TextDataFormat.UnicodeText) : null;
                }
                catch (COMException) { Thread.Sleep(20); }
            }
            return null;
        }

        void ShowMain()
        {
            if (!IsVisible) Show();
            if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
            Topmost = true; Activate(); Topmost = false;
        }

        void Input_TextChanged(object sender, TextChangedEventArgs e)
        {
            Render(Input.Text);
        }

        void Render(string text)
        {
            if (string.IsNullOrEmpty(text))
            {
                QrImage.Source = null;
                return;
            }
            try
            {
                var gen = new QRCodeGenerator();
                var data = gen.CreateQrCode(text, QRCodeGenerator.ECCLevel.M, forceUtf8: true, utf8BOM: false);
                var m = data.ModuleMatrix;
                int n = m.Count;
                int s = Math.Max(2, 480 / n);
                int size = n * s;
                var px = new byte[size * size];
                for (int y = 0; y < n; y++)
                    for (int x = 0; x < n; x++)
                    {
                        byte v = m[y][x] ? (byte)0 : (byte)255;
                        for (int dy = 0; dy < s; dy++)
                        {
                            int row = (y * s + dy) * size + x * s;
                            for (int dx = 0; dx < s; dx++) px[row + dx] = v;
                        }
                    }
                QrImage.Source = BitmapSource.Create(size, size, 96, 96, PixelFormats.Gray8, null, px, size);
                Status.Text = text.Length + " 字符";
            }
            catch (Exception)
            {
                QrImage.Source = null;
                Status.Text = "生成失败：内容过长";
            }
        }

        void Window_Closing(object sender, System.ComponentModel.CancelEventArgs e)
        {
            if (quitting) return;
            e.Cancel = true;
            Hide();
        }

        void Quit()
        {
            quitting = true;
            Native.UnregisterHotKey(hwnd, HOTKEY_ID);
            tray.Visible = false;
            tray.Dispose();
            Application.Current.Shutdown();
        }
    }
}
