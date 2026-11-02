* A render that crashed on another node no longer blocks its study until someone deletes the lock. A running render keeps a
  heartbeat in the lock from its own node, and a lock whose heartbeat has stopped for ten minutes is taken over. A lock with no
  heartbeat, from an older release, still reads as running and names the directory to delete.
