import std/[locks, deques, atomics]

type
  TaskQueue*[T] = object
    lock: Lock
    cond: Cond
    queue: Deque[T]
    activeWorkers: Atomic[int]
    totalWorkers: int
    shutdown: Atomic[bool]

proc initTaskQueue*[T](tq: var TaskQueue[T], workers: int) =
  initLock(tq.lock)
  initCond(tq.cond)
  tq.queue = initDeque[T]()
  tq.activeWorkers.store(0)
  tq.totalWorkers = workers
  tq.shutdown.store(false)

proc push*[T](tq: var TaskQueue[T], item: T) =
  acquire(tq.lock)
  tq.queue.addLast(item)
  signal(tq.cond)
  release(tq.lock)

proc pushBatch*[T](tq: var TaskQueue[T], items: seq[T]) =
  if items.len == 0: return
  acquire(tq.lock)
  for item in items:
    tq.queue.addLast(item)
  signal(tq.cond)
  release(tq.lock)

proc tryPop*[T](tq: var TaskQueue[T], item: var T): bool =
  ## Try to get an item. Returns false if queue is empty and all workers are done.
  acquire(tq.lock)
  while tq.queue.len == 0:
    if tq.shutdown.load():
      release(tq.lock)
      return false
    # Check if all other workers are also idle → we're done
    let active = tq.activeWorkers.load()
    if active == 0:
      # No one is working, queue is empty → signal shutdown
      tq.shutdown.store(true)
      broadcast(tq.cond)
      release(tq.lock)
      return false
    # Wait for new items
    wait(tq.cond, tq.lock)

  item = tq.queue.popFirst()
  release(tq.lock)
  return true

proc markActive*[T](tq: var TaskQueue[T]) =
  discard tq.activeWorkers.fetchAdd(1)

proc markIdle*[T](tq: var TaskQueue[T]) =
  let prev = tq.activeWorkers.fetchSub(1)
  if prev == 1:
    # Was last active worker, might be time to shutdown
    acquire(tq.lock)
    if tq.queue.len == 0:
      tq.shutdown.store(true)
      broadcast(tq.cond)
    release(tq.lock)

proc isShutdown*[T](tq: var TaskQueue[T]): bool =
  tq.shutdown.load()
