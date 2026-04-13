(in-package #:hegel)

(defvar *connection* nil
  "The current Hegel connection. Bind with with-connection or set directly.")

(defvar *current-stream-id* nil
  "Stream ID for the current test case. Bound by the runner during test execution.")

(defun generate (schema)
  "Generate a value from SCHEMA. Must be called within a run-property body."
  (let ((result (send-command *connection* *current-stream-id*
                              `(("command" . "generate")
                                ("schema" . ,schema)))))
    (cdr (assoc "result" result :test #'string=))))

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
  (send-reply conn pkt-stream-id pkt-msg-id
              (alist-to-hash-table '(("result" . nil))))
  ;; Run body, determine status — commands go on tc-stream-id
  (let ((*current-stream-id* tc-stream-id)
        (status "VALID")
        (origin nil))
    (handler-case
        (handler-case (funcall body-fn)
          (invalid-test-case ()
            (setf status "INVALID")))
      (error (e)
        (setf status "INTERESTING"
              origin (princ-to-string e))))
    ;; Send mark_complete on test case stream
    (send-command conn tc-stream-id
                  `(("command" . "mark_complete")
                    ("status" . ,status)
                    ,@(when origin `(("origin" . ,origin)))))
    ;; Send stream_close on test case stream
    (send-stream-close conn tc-stream-id)
    status))

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
    (let ((counterexample nil)
          (final-counterexample nil))
      (loop
        (multiple-value-bind (msg stream-id message-id) (read-message conn)
          (let ((event (msg-field msg "event")))
            (cond
              ;; test_done: break out
              ((string= event "test_done")
               (let* ((results (msg-field msg "results"))
                      (passed (msg-field results "passed"))
                      (result (make-test-result
                               :passed (if passed t nil)
                               :test-cases (msg-field results "test_cases")
                               :valid-test-cases (msg-field results "valid_test_cases")
                               :invalid-test-cases (msg-field results "invalid_test_cases")
                               :interesting-test-cases (msg-field results "interesting_test_cases")
                               :seed (msg-field results "seed")
                               :counterexample final-counterexample
                               :error (msg-field results "error"))))
                 ;; Send test_done reply
                 (send-reply conn stream-id message-id
                             (alist-to-hash-table '(("result" . t))))
                 ;; Handle final replays — one per interesting test case
                 (let ((n-interesting (or (msg-field results "interesting_test_cases") 0)))
                   (dotimes (_ n-interesting)
                     (multiple-value-bind (replay-msg replay-sid replay-mid)
                         (read-message conn)
                       (let ((replay-tc-sid (msg-field replay-msg "stream_id")))
                         (run-test-case conn body-fn replay-sid replay-mid replay-tc-sid))))
                   (unless passed
                     (signal 'property-failed
                             :name name
                             :counterexample final-counterexample
                             :seed (test-result-seed result)
                             :test-cases-run (test-result-test-cases result))))
                 (return result)))
              ;; test_case: run it
              ((string= event "test_case")
               (let ((tc-stream-id (msg-field msg "stream_id"))
                     (is-final (msg-field msg "is_final")))
                 (declare (ignore is-final))
                 (run-test-case conn body-fn stream-id message-id tc-stream-id))))))))))
