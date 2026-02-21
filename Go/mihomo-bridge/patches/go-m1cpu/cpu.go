// Stub replacement for go-m1cpu that avoids IOKit APIs unavailable on iOS.

package m1cpu

func IsAppleSilicon() bool    { return false }
func PCoreHz() uint64         { return 0 }
func ECoreHz() uint64         { return 0 }
func PCoreGHz() float64       { return 0 }
func ECoreGHz() float64       { return 0 }
func PCoreCount() int         { return 0 }
func ECoreCount() int         { return 0 }
func PCoreCache() (int, int, int) { return 0, 0, 0 }
func ECoreCache() (int, int, int) { return 0, 0, 0 }
func ModelName() string       { return "unknown" }
