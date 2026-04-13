(in-package #:hegel)

(defun convert-value (val)
  "Convert a value for CBOR encoding: alists become hash tables, plain lists become vectors."
  (cond
    ((and (consp val) (consp (car val)) (stringp (caar val)))
     (alist-to-hash-table val))
    ((consp val)
     (map 'vector #'convert-value val))
    (t val)))

(defun alist-to-hash-table (alist)
  "Convert an alist with string keys to a hash table for CBOR encoding.
Recursively converts nested alists to hash tables and plain lists to vectors."
  (let ((ht (make-hash-table :test #'equal)))
    (dolist (pair alist ht)
      (setf (gethash (car pair) ht)
            (convert-value (cdr pair))))))

(defun encode-cbor (alist)
  "Encode an alist as CBOR bytes (via hash table)."
  (let ((cbor:*use-stringrefs* nil)
        (cbor:*use-sharedrefs* nil))
    (coerce (cbor:encode (alist-to-hash-table alist))
            '(simple-array (unsigned-byte 8) (*)))))

(defun hegel-tag-reader (tag data)
  "Handle Hegel-specific CBOR tags. Tag 91 = WTF-8 string (UTF-8 allowing surrogates)."
  (case tag
    (91 (let ((bytes (coerce data '(simple-array (unsigned-byte 8) (*)))))
          (handler-case
              (flexi-streams:octets-to-string bytes :external-format :utf-8)
            (error ()
              ;; WTF-8 with lone surrogates — fall back to latin-1 for lossless byte→char
              (flexi-streams:octets-to-string bytes :external-format :latin-1)))))
    (t data)))

(defun decode-cbor (bytes)
  "Decode CBOR bytes to an alist."
  (let ((cbor:*dictionary-format* :alist)
        (cbor:*custom-tag-reader* #'hegel-tag-reader))
    (cbor:decode bytes)))

(defvar *protocol-debug* nil
  "When true, print protocol trace messages to *error-output*.")

(defun protocol-log (fmt &rest args)
  (when *protocol-debug*
    (apply #'format *error-output* fmt args)
    (force-output *error-output*)))

(defun send-command (conn stream-id command-alist)
  "Send a CBOR-encoded command on STREAM-ID. Waits for and returns the decoded reply.
Server-initiated events received while waiting are queued in pending-events."
  (let* ((payload (encode-cbor command-alist))
         (msg-id (next-message-id conn stream-id))
         (pkt (make-packet :stream-id stream-id
                           :message-id msg-id
                           :payload-length (length payload)
                           :payload payload)))
    (protocol-log "[send-command] stream=~A msg=~A payload=~A bytes cmd=~A~%"
                  stream-id msg-id (length payload)
                  (cdr (assoc "command" command-alist :test #'string=)))
    (write-hegel-packet (connection-output conn) pkt)
    (protocol-log "[send-command] packet written, waiting for reply...~%")
    ;; Read packets until we get a reply (reply bit set)
    (loop
      (let ((reply (read-hegel-packet (connection-input conn))))
        (cond
          ((reply-p (packet-message-id reply))
           ;; This is a reply — return it
           (let ((reply-data (decode-cbor (packet-payload reply))))
             (protocol-log "[send-command] got reply stream=~A msg=~A data=~A~%"
                           (packet-stream-id reply) (packet-message-id reply) reply-data)
             (return reply-data)))
          (t
           ;; Server-initiated event — queue it
           (let ((data (decode-cbor (packet-payload reply))))
             (protocol-log "[send-command] queued event stream=~A msg=~A data=~A~%"
                           (packet-stream-id reply) (packet-message-id reply) data)
             (setf (connection-pending-events conn)
                   (nconc (connection-pending-events conn)
                          (list (list data
                                      (packet-stream-id reply)
                                      (packet-message-id reply))))))))))))

(defun send-stream-close (conn stream-id)
  "Send a stream_close packet (raw 0xFE payload, message-id = (1 << 31) - 1)."
  (let* ((payload (make-array 1 :element-type '(unsigned-byte 8)
                                :initial-element #xFE))
         (pkt (make-packet :stream-id stream-id
                           :message-id #x7FFFFFFF
                           :payload-length 1
                           :payload payload)))
    (write-hegel-packet (connection-output conn) pkt)))

(defun send-reply (conn stream-id orig-message-id reply-alist)
  "Send a CBOR-encoded reply to a server request. REPLY-ALIST is encoded as CBOR."
  (protocol-log "[send-reply] stream=~A orig-msg=~A data=~A~%" stream-id orig-message-id reply-alist)
  (let* ((payload (encode-cbor reply-alist))
         (pkt (make-packet :stream-id stream-id
                           :message-id (make-reply-id orig-message-id)
                           :payload-length (length payload)
                           :payload payload)))
    (write-hegel-packet (connection-output conn) pkt)))

(defun read-message (conn)
  "Read and decode a CBOR message from the server.
Returns (values decoded-data stream-id message-id).
Drains pending-events queue first before reading from the wire."
  (let ((pending (connection-pending-events conn)))
    (if pending
        (let ((entry (pop (connection-pending-events conn))))
          (destructuring-bind (data stream-id message-id) entry
            (protocol-log "[read-message] from queue stream=~A msg=~A data=~A~%"
                          stream-id message-id data)
            (values data stream-id message-id)))
        (progn
          (protocol-log "[read-message] waiting on wire...~%")
          (let* ((pkt (read-hegel-packet (connection-input conn)))
                 (data (decode-cbor (packet-payload pkt))))
            (protocol-log "[read-message] stream=~A msg=~A data=~A~%"
                          (packet-stream-id pkt) (packet-message-id pkt) data)
            (values data (packet-stream-id pkt) (packet-message-id pkt)))))))
