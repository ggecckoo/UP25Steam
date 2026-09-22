//go:build !windows

package game

import "os"

func platformLocale() string {
	if v := os.Getenv("LC_ALL"); v != "" {
		return v
	}
	if v := os.Getenv("LANG"); v != "" {
		return v
	}
	return ""
}
