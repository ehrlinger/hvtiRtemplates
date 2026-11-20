* When a background-job test's process never shows its marker, the failure now
  names the process's status, command line and children, and a process killed
  by a signal but not yet reaped is read as dead, not as still running (#587).
