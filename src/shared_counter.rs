use std::{
    mem::{align_of, size_of},
    sync::atomic::{AtomicI32, Ordering},
};

const SLOT_SIZE: usize = size_of::<AtomicI32>();

unsafe fn slot<'a>(counter: *mut u8, index: usize) -> &'a AtomicI32 {
    let ptr = counter.add(index * SLOT_SIZE);
    debug_assert_eq!(ptr as usize % align_of::<AtomicI32>(), 0);
    &*(ptr as *const AtomicI32)
}

pub(crate) unsafe fn reset(counter: *mut u8) {
    slot(counter, 1).store(0, Ordering::SeqCst);
    slot(counter, 0).store(0, Ordering::SeqCst);
}

pub(crate) unsafe fn pending(counter: *mut u8) -> Option<i32> {
    let written = slot(counter, 0).load(Ordering::Acquire);
    let consumed = slot(counter, 1).load(Ordering::Acquire);
    (written != consumed).then_some(written)
}

pub(crate) unsafe fn consume(counter: *mut u8, sequence: i32) {
    slot(counter, 1).store(sequence, Ordering::Release);
}

pub(crate) unsafe fn consume_pending(counter: *mut u8, pending: &mut Option<i32>) {
    if let Some(sequence) = pending.take() {
        consume(counter, sequence);
    }
}

pub(crate) unsafe fn equal(counter: *mut u8) -> bool {
    slot(counter, 0).load(Ordering::Acquire) == slot(counter, 1).load(Ordering::Acquire)
}

pub(crate) unsafe fn publish(counter: *mut u8) {
    let write = slot(counter, 0);
    let read = slot(counter, 1);
    let current = write.load(Ordering::Relaxed);
    let next = if current == i32::MAX { 0 } else { current + 1 };
    if read.load(Ordering::Acquire) == next {
        read.store(current, Ordering::Release);
    }
    write.store(next, Ordering::Release);
}

#[cfg(test)]
mod tests {
    use super::{consume, consume_pending, equal, pending, publish, reset};
    use std::sync::atomic::AtomicI32;

    fn ptr(counter: &[AtomicI32; 2]) -> *mut u8 {
        counter.as_ptr() as *mut u8
    }

    #[test]
    fn published_value_stays_pending_until_consumed() {
        let counter = [AtomicI32::new(0), AtomicI32::new(0)];
        unsafe {
            reset(ptr(&counter));
            assert!(equal(ptr(&counter)));
            assert_eq!(pending(ptr(&counter)), None);

            publish(ptr(&counter));
            assert!(!equal(ptr(&counter)));
            assert_eq!(pending(ptr(&counter)), Some(1));

            consume(ptr(&counter), 1);
            assert!(equal(ptr(&counter)));
            assert_eq!(pending(ptr(&counter)), None);
        }
    }

    #[test]
    fn reset_discards_an_unconsumed_frame() {
        let counter = [AtomicI32::new(0), AtomicI32::new(0)];
        unsafe {
            publish(ptr(&counter));
            assert_eq!(pending(ptr(&counter)), Some(1));
            reset(ptr(&counter));
            assert_eq!(pending(ptr(&counter)), None);
        }
    }

    #[test]
    fn pending_frame_is_consumed_when_reader_is_cleaned_up() {
        let counter = [AtomicI32::new(0), AtomicI32::new(0)];
        unsafe {
            publish(ptr(&counter));
            let mut reader_pending = pending(ptr(&counter));
            assert_eq!(reader_pending, Some(1));

            consume_pending(ptr(&counter), &mut reader_pending);

            assert_eq!(reader_pending, None);
            assert!(equal(ptr(&counter)));
        }
    }

    #[test]
    fn wraparound_never_looks_consumed() {
        let counter = [AtomicI32::new(i32::MAX), AtomicI32::new(0)];
        unsafe {
            publish(ptr(&counter));
            assert_eq!(pending(ptr(&counter)), Some(0));
            consume(ptr(&counter), 0);
            assert!(equal(ptr(&counter)));
        }
    }
}
