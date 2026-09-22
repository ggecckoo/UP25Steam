//go:build windows

package game

import (
	"os"
	"syscall"
	"unsafe"
)

func platformLocale() string {
	if v := os.Getenv("LC_ALL"); v != "" {
		return v
	}
	if v := os.Getenv("LANG"); v != "" {
		return v
	}
	kernel32 := syscall.NewLazyDLL("kernel32.dll")
	proc := kernel32.NewProc("GetUserDefaultLocaleName")
	buf := make([]uint16, 85)
	r, _, _ := proc.Call(uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
	if r == 0 {
		return ""
	}
	return syscall.UTF16ToString(buf)
}
