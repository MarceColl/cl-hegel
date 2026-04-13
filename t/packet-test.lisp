(in-package #:hegel/tests)

(in-suite packet-suite)

;;; Bit manipulation helpers

(test make-reply-id-sets-bit-31
  (is (= #x80000000 (make-reply-id 0)))
  (is (= #x80000005 (make-reply-id 5)))
  (is (= #x80000001 (make-reply-id 1))))

(test reply-p-checks-bit-31
  (is (reply-p #x80000000))
  (is (reply-p #x80000005))
  (is (not (reply-p 0)))
  (is (not (reply-p 5))))

(test make-client-stream-id-sets-bit-31
  (is (= #x80000001 (make-client-stream-id 1)))
  (is (= #x80000002 (make-client-stream-id 2))))

;;; Checksum

(test compute-checksum-returns-uint32
  (let* ((bytes (make-array 20 :element-type '(unsigned-byte 8) :initial-element 0))
         (result (compute-checksum bytes)))
    (is (typep result '(unsigned-byte 32)))
    (is (plusp result))))

;;; write-hegel-packet wire format

(test write-hegel-packet-empty-payload
  "Empty payload: 20 header + 0 payload + 1 terminator = 21 bytes"
  (let ((pkt (make-packet :stream-id 0 :message-id 0
                          :payload-length 0
                          :payload (make-array 0 :element-type '(unsigned-byte 8)))))
    (flexi-streams:with-output-to-sequence (out :element-type '(unsigned-byte 8))
      (write-hegel-packet out pkt)
      (let ((bytes (flexi-streams:get-output-stream-sequence out)))
        ;; Magic "HEGL"
        (is (= #x48 (aref bytes 0)))
        (is (= #x45 (aref bytes 1)))
        (is (= #x47 (aref bytes 2)))
        (is (= #x4C (aref bytes 3)))
        ;; Checksum is non-zero (computed)
        (is (not (every #'zerop (subseq bytes 4 8))))
        ;; Terminator is last byte
        (is (= #x0A (aref bytes (1- (length bytes)))))))))

;;; Round-trip

(test read-write-round-trip
  (let* ((payload (make-array 5 :element-type '(unsigned-byte 8)
                                :initial-contents '(1 2 3 4 5)))
         (pkt (make-packet :stream-id 42 :message-id 7
                           :payload-length 5 :payload payload)))
    (let ((wire-bytes
            (flexi-streams:with-output-to-sequence (out :element-type '(unsigned-byte 8))
              (write-hegel-packet out pkt))))
      (flexi-streams:with-input-from-sequence (in wire-bytes)
        (let ((result (read-hegel-packet in)))
          (is (= 42 (packet-stream-id result)))
          (is (= 7 (packet-message-id result)))
          (is (= 5 (packet-payload-length result)))
          (is (equalp payload (packet-payload result))))))))

(test checksum-mismatch-signals-error
  (let* ((payload (make-array 3 :element-type '(unsigned-byte 8)
                                :initial-contents '(10 20 30)))
         (pkt (make-packet :stream-id 1 :message-id 2
                           :payload-length 3 :payload payload)))
    (let ((wire-bytes
            (flexi-streams:with-output-to-sequence (out :element-type '(unsigned-byte 8))
              (write-hegel-packet out pkt))))
      ;; Corrupt a payload byte
      (setf (aref wire-bytes 22) 99)
      (signals error
        (flexi-streams:with-input-from-sequence (in wire-bytes)
          (read-hegel-packet in))))))
