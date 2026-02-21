// Stub replacement for gopsutil/process to avoid macOS-only libproc.h on iOS.

package process

import "context"

type Process struct {
	Pid int32 `json:"pid"`
}

type MemoryInfoStat struct {
	RSS    uint64 `json:"rss"`
	VMS    uint64 `json:"vms"`
	HWM    uint64 `json:"hwm"`
	Data   uint64 `json:"data"`
	Stack  uint64 `json:"stack"`
	Locked uint64 `json:"locked"`
	Swap   uint64 `json:"swap"`
}

func NewProcess(pid int32) (*Process, error) {
	return &Process{Pid: pid}, nil
}

func NewProcessWithContext(_ context.Context, pid int32) (*Process, error) {
	return &Process{Pid: pid}, nil
}

func (p *Process) MemoryInfo() (*MemoryInfoStat, error) {
	return &MemoryInfoStat{}, nil
}

func (p *Process) MemoryInfoWithContext(_ context.Context) (*MemoryInfoStat, error) {
	return &MemoryInfoStat{}, nil
}
