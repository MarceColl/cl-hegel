(in-package #:hegel)

(defun make-reply-id (message-id)
  (logior message-id #x80000000))

(defun reply-p (message-id)
  (logbitp 31 message-id))

(defun make-client-stream-id (id)
  (logior id #x80000000))

(defconstant +terminator+ #x0A)

(defbinary packet (:byte-order :big-endian)
  (magic #x4845474C :type (magic :actual-type (unsigned-byte 32)
                                  :value #x4845474C))
  (checksum 0 :type (unsigned-byte 32))
  (stream-id 0 :type (unsigned-byte 32))
  (message-id 0 :type (unsigned-byte 32))
  (payload-length 0 :type (unsigned-byte 32))
  (payload (make-array 0 :element-type '(unsigned-byte 8))
           :type (simple-array (unsigned-byte 8) (payload-length))))

(defun compute-checksum (bytes)
  "Compute CRC32 over a byte vector, returning a uint32."
  (let* ((simple-bytes (coerce bytes '(simple-array (unsigned-byte 8) (*))))
         (digest (ironclad:make-digest :crc32)))
    (ironclad:update-digest digest simple-bytes)
    (let ((result (ironclad:produce-digest digest)))
      (logior (ash (aref result 0) 24)
              (ash (aref result 1) 16)
              (ash (aref result 2) 8)
              (aref result 3)))))

(defun write-hegel-packet (stream pkt)
  "Write PKT to STREAM with checksum and terminator."
  (setf (packet-checksum pkt) 0)
  (let* ((raw (flexi-streams:with-output-to-sequence (tmp :element-type '(unsigned-byte 8))
                (write-binary pkt tmp)))
         (crc (compute-checksum raw)))
    ;; Patch checksum into bytes 4-7 (big-endian)
    (setf (aref raw 4) (ldb (byte 8 24) crc)
          (aref raw 5) (ldb (byte 8 16) crc)
          (aref raw 6) (ldb (byte 8 8) crc)
          (aref raw 7) (ldb (byte 8 0) crc))
    (write-sequence raw stream)
    (write-byte +terminator+ stream)
    (force-output stream)))

(defun read-hegel-packet (stream)
  "Read a packet from STREAM. Verifies magic, checksum, and terminator."
  (let ((pkt (read-binary 'packet stream)))
    (let ((term (read-byte stream)))
      (unless (= term +terminator+)
        (error "Invalid terminator: ~2,'0X" term)))
    ;; Verify checksum: re-serialize with checksum=0 and compare
    (let ((stored-checksum (packet-checksum pkt)))
      (setf (packet-checksum pkt) 0)
      (let* ((raw (flexi-streams:with-output-to-sequence (tmp :element-type '(unsigned-byte 8))
                    (write-binary pkt tmp)))
             (computed (compute-checksum raw)))
        (unless (= stored-checksum computed)
          (error "Checksum mismatch: expected ~8,'0X got ~8,'0X"
                 stored-checksum computed))
        (setf (packet-checksum pkt) stored-checksum)
        pkt))))
