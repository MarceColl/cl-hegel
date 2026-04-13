(in-package #:hegel)

(defstruct (connection (:constructor %make-connection))
  (output nil)  ; binary stream we write to (server's stdin)
  (input nil)   ; binary stream we read from (server's stdout)
  (process nil)  ; uiop process-info, nil for mock connections
  (stream-id-counter 0 :type (unsigned-byte 32))
  (stream-message-ids (make-hash-table) :type hash-table)  ; per-stream msg counters
  (handshake-done-p nil :type boolean)
  (pending-events nil :type list))

(defun make-connection-from-streams (output input)
  "Create a connection from pre-existing streams (for testing or custom transports)."
  (%make-connection :output output :input input))

(defun next-message-id (conn stream-id)
  "Allocate and return the next message ID for STREAM-ID. Per-stream, starting at 1."
  (let ((table (connection-stream-message-ids conn)))
    (incf (gethash stream-id table 0))))

(defun next-stream-id (conn)
  "Allocate and return the next client stream ID.
Client streams use format (counter << 1) | 1, with bit 31 set."
  (incf (connection-stream-id-counter conn))
  (make-client-stream-id (logior (ash (connection-stream-id-counter conn) 1) 1)))

(defun start-hegel-core ()
  "Spawn hegel-core via uv and return a connection.
Respects HEGEL_SERVER_COMMAND env var if set."
  (let* ((command (or (uiop:getenv "HEGEL_SERVER_COMMAND")
                      "PYTHONUNBUFFERED=1 uv tool run --from hegel-core hegel --stdio"))
         (process (uiop:launch-program command
                                       :input :stream
                                       :output :stream
                                       :element-type '(unsigned-byte 8))))
    (%make-connection
     :output (uiop:process-info-input process)
     :input (uiop:process-info-output process)
     :process process)))

(defun close-connection (conn)
  "Close a connection and terminate the subprocess if any."
  (when (connection-process conn)
    (ignore-errors (close (connection-output conn)))
    (ignore-errors (close (connection-input conn)))
    (uiop:terminate-process (connection-process conn))
    (uiop:wait-process (connection-process conn)))
  (values))

(defun ensure-connection ()
  "Return *connection*, creating one if nil."
  (unless *connection*
    (setf *connection* (start-hegel-core))
    (perform-handshake *connection*))
  *connection*)

(defmacro with-connection ((&key server-command) &body body)
  "Execute BODY with a fresh hegel-core connection bound to *connection*."
  (let ((conn (gensym "CONN")))
    `(let* ((,conn (let (,@(when server-command
                             `((*hegel-server-command* ,server-command))))
                     (start-hegel-core)))
            (*connection* ,conn))
       (unwind-protect
            (progn
              (perform-handshake ,conn)
              ,@body)
         (close-connection ,conn)))))

(defun perform-handshake (conn)
  "Perform the Hegel handshake. Must be called once before any other communication."
  (let* ((payload (flexi-streams:string-to-octets "hegel_handshake_start"
                                                   :external-format :ascii))
         (msg-id (next-message-id conn 0))
         (pkt (make-packet :stream-id 0
                           :message-id msg-id
                           :payload-length (length payload)
                           :payload (coerce payload '(simple-array (unsigned-byte 8) (*))))))
    (write-hegel-packet (connection-output conn) pkt)
    ;; Read reply
    (let* ((reply (read-hegel-packet (connection-input conn)))
           (reply-text (flexi-streams:octets-to-string
                        (packet-payload reply)
                        :external-format :ascii)))
      (unless (and (reply-p (packet-message-id reply))
                   (>= (length reply-text) 6)
                   (string= "Hegel/" (subseq reply-text 0 6)))
        (error "Invalid handshake reply: ~A" reply-text))
      (setf (connection-handshake-done-p conn) t))))
