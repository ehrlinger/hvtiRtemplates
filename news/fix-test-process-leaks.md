* A render lock's heartbeat loop now ends when its lock is released, not only when the
  process that owns the lock exits. A long-lived owner, such as a test suite's driver, kept one
  `sh` loop and its `sleep 60` running for every lock it had taken (#599).
