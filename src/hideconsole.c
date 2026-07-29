#include <windows.h>

static void _hide_console_func(void) { FreeConsole(); }

#pragma section(".CRT$XCA", long, read)
__declspec(allocate(".CRT$XCA")) void (*_hide_console)(void) = _hide_console_func;
