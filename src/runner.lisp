(in-package #:hegel)

(defvar *current-stream-id* nil
  "Stream ID for the current test case. Bound by the runner during test execution.")

(defun generate (schema)
  "Generate a value from SCHEMA. Must be called within a run-property body.
Signals TEST-ABORTED if hegel-core returns an error (StopTest, Overflow, etc)."
  (let ((result (send-command *connection* *current-stream-id*
                              `(("command" . "generate")
                                ("schema" . ,schema)))))
    (when (msg-field result "type")
      (signal 'test-aborted))
    (msg-field result "result")))

(defun assume (predicate)
  "Skip this test case if PREDICATE is false."
  (unless predicate
    (signal 'invalid-test-case)))

(defun msg-field (msg field)
  (cdr (assoc field msg :test #'string=)))

(defun run-test-case (conn body-fn pkt-stream-id pkt-msg-id tc-stream-id)
  "Execute a single test case. Returns the mark_complete status string.
PKT-STREAM-ID/PKT-MSG-ID are from the test_case packet (for the reply).
TC-STREAM-ID is the CBOR stream_id (for generate/mark_complete commands)."
  ;; Send test_case_reply on the run stream (where the event arrived)
  (send-reply conn pkt-stream-id pkt-msg-id '(("result" . nil)))
  ;; Run body, determine status — commands go on tc-stream-id
  (let ((*current-stream-id* tc-stream-id)
        (status "VALID")
        (origin nil)
        (aborted nil))
    (handler-case
        (handler-case (funcall body-fn)
          (test-aborted ()
            (setf aborted t))
          (invalid-test-case ()
            (setf status "INVALID")))
      (error (e)
        (setf status "INTERESTING"
              origin (princ-to-string e))))
    ;; Skip mark_complete and stream_close if hegel-core already closed the stream
    (unless aborted
      (send-command conn tc-stream-id
                    `(("command" . "mark_complete")
                      ("status" . ,status)
                      ,@(when origin `(("origin" . ,origin)))))
      (send-stream-close conn tc-stream-id))
    status))

(defun unpack-uleb128 (buffer &optional (start 0))
  "Returns (values value bytes-consumed)"
  (let ((result 0)
        (shift 0)
        (idx start))
    (loop
      (let ((byte (aref buffer idx)))
        (incf idx)
        (setf result (logior result (ash (logand byte #x7f) shift)))
        (incf shift 7)
        (when (zerop (logand byte #x80))
          (return (values result (- idx start))))))))

(defun bytes-to-signed-integer (bytes)
  (let* ((nbits (* 8 (length bytes)))
         (unsigned (loop for b across bytes
                         for shift from (- nbits 8) downto 0 by 8
                         sum (ash b shift))))
    (if (logbitp (1- nbits) unsigned)
        (- unsigned (ash 1 nbits))
        unsigned)))

(defun choices-from-bytes (buffer)
  (let ((parts '())
        (idx 0)
        (len (length buffer)))
    (loop while (< idx len) do
      (let* ((byte (aref buffer idx))
             (tag  (ash byte -5))
             (size (logand byte #b11111)))
        (incf idx)
        (if (= tag 0)
            (push (not (zerop size)) parts)
            (progn
              (when (= size #b11111)
                (multiple-value-bind (val offset)
                    (unpack-uleb128 buffer idx)
                  (setf size val)
                  (incf idx offset)))
              (let ((chunk (subseq buffer idx (+ idx size))))
                (incf idx size)
                (push (ecase tag
                        (1 (progn
                             (assert (= size 8) () "expected float64")
                             (ieee-floats:decode-float64
                              (nibbles:ub64ref/be chunk 0))))
                        (2 (bytes-to-signed-integer chunk))
                        (3 chunk)
                        (4 (babel:octets-to-string chunk :encoding :utf-8)))
                      parts))))))
    (coerce (nreverse parts) 'vector)))

(defun decode-failure (failure-blob)
  (let ((b64-string (map 'string #'code-char failure-blob)))
    (multiple-value-bind (decoded) (cl-base64:base64-string-to-usb8-array b64-string)
      (let* ((prefix (aref decoded 0))
             (rest (make-array (1- (length decoded))
                    :element-type (array-element-type decoded)
                    :displaced-to decoded
                    :displaced-index-offset 1))
             (decoded-bytes (if (= prefix 0) rest (error "Compressed payloads not supported yet"))))
        (choices-from-bytes decoded-bytes)))))

(defun decode-failures (failure-blobs)
  (map 'list #'decode-failure failure-blobs))

(defun run-property (name body-fn &key (test-cases 100) seed)
  "Run a property-based test. BODY-FN is a zero-argument function that calls GENERATE
and signals errors on failure. Returns a TEST-RESULT. Signals PROPERTY-FAILED on failure.
Automatically creates a connection if *connection* is nil."
  (ensure-connection)
  (let* ((conn *connection*)
         (run-stream-id (next-stream-id conn)))
    ;; Phase 1: Send run_test on control stream (0), with new stream_id in payload
    (send-command conn 0
                  `(("command" . "run_test")
                    ("stream_id" . ,run-stream-id)
                    ("test_cases" . ,test-cases)
                    ,@(when seed `(("seed" . ,seed)))
                    ("database_key" . ,(flexi-streams:string-to-octets
                                        name :external-format :utf-8))))
    ;; Phase 2: Test case loop
    (loop
      (multiple-value-bind (msg stream-id message-id) (read-message conn)
        (let ((event (msg-field msg "event")))
          (cond
            ;; test_done: break out
            ((string= event "test_done")
             (let* ((results (msg-field msg "results"))
                    (passed (msg-field results "passed"))
                    (counterexample (decode-failures (msg-field results "failure_blobs")))
                    (result (make-test-result
                             :passed (if passed t nil)
                             :test-cases (msg-field results "test_cases")
                             :valid-test-cases (msg-field results "valid_test_cases")
                             :invalid-test-cases (msg-field results "invalid_test_cases")
                             :interesting-test-cases (msg-field results "interesting_test_cases")
                             :seed (msg-field results "seed")
                             :counterexample counterexample
                             :error (msg-field results "error"))))
               ;; Send test_done reply
               (send-reply conn stream-id message-id '(("result" . t)))
               ;; Handle final replays, one per interesting test case
               (let ((n-interesting (or (msg-field results "interesting_test_cases") 0)))
                 (dotimes (_ n-interesting)
                   (multiple-value-bind (replay-msg replay-sid replay-mid)
                       (read-message conn)
                     (let ((replay-tc-sid (msg-field replay-msg "stream_id")))
                       (run-test-case conn body-fn replay-sid replay-mid replay-tc-sid))))
                 (unless passed
                   (signal 'property-failed
                           :name name
                           :seed (test-result-seed result)
                           :counterexample counterexample
                           :test-cases-run (test-result-test-cases result))))
               (return result)))
            ;; test_case: run it
            ((string= event "test_case")
             (let ((tc-stream-id (msg-field msg "stream_id")))
               (run-test-case conn body-fn stream-id message-id tc-stream-id)))))))))
