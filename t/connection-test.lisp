(in-package #:hegel/tests)

(def-suite connection-suite
  :description "Connection management tests"
  :in hegel-suite)

(in-suite connection-suite)

;;; Connection struct and ID allocation

(test next-message-id-is-per-stream
  (let ((conn (make-connection-from-streams
               (make-broadcast-stream) (make-concatenated-stream))))
    ;; Per-stream counters, starting at 1
    (is (= 1 (next-message-id conn 0)))
    (is (= 2 (next-message-id conn 0)))
    ;; Different stream starts fresh
    (is (= 1 (next-message-id conn 5)))
    (is (= 3 (next-message-id conn 0)))))

(test next-stream-id-format
  "Client stream IDs use (counter << 1) | 1 with bit 31 set"
  (let ((conn (make-connection-from-streams
               (make-broadcast-stream) (make-concatenated-stream))))
    (let ((id1 (next-stream-id conn))
          (id2 (next-stream-id conn)))
      ;; counter=1: (1 << 1) | 1 = 3, with bit 31 = 0x80000003
      (is (= #x80000003 id1))
      ;; counter=2: (2 << 1) | 1 = 5, with bit 31 = 0x80000005
      (is (= #x80000005 id2)))))

;;; Handshake over mock streams

(test perform-handshake-sends-and-receives
  "Handshake sends 'hegel_handshake_start' and expects 'Hegel/...' reply"
  (let* ((client-to-server (flexi-streams:make-in-memory-output-stream
                            :element-type '(unsigned-byte 8)))
         ;; Build a fake handshake reply packet
         (reply-payload (flexi-streams:string-to-octets "Hegel/0.1.0"
                                                        :external-format :ascii))
         (reply-bytes
           (flexi-streams:with-output-to-sequence (tmp :element-type '(unsigned-byte 8))
             (write-hegel-packet tmp
               (make-packet :stream-id 0
                            :message-id (make-reply-id 1)
                            :payload-length (length reply-payload)
                            :payload reply-payload))))
         (server-to-client (flexi-streams:make-in-memory-input-stream reply-bytes))
         (conn (make-connection-from-streams client-to-server server-to-client)))
    (perform-handshake conn)
    (is (connection-handshake-done-p conn))
    ;; Verify client sent a packet with "hegel_handshake_start" payload
    (let* ((sent-bytes (flexi-streams:get-output-stream-sequence client-to-server))
           (sent-pkt (flexi-streams:with-input-from-sequence (in sent-bytes)
                       (read-hegel-packet in)))
           (sent-text (flexi-streams:octets-to-string (packet-payload sent-pkt)
                                                      :external-format :ascii)))
      (is (string= "hegel_handshake_start" sent-text))
      (is (= 0 (packet-stream-id sent-pkt))))))
