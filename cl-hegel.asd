(asdf:defsystem #:cl-hegel
  :depends-on (#:lisp-binary #:ironclad #:cbor)
  :serial t
  :components ((:module "src"
                :components
                ((:file "package")
                 (:file "packet")
                 (:file "connection")
                 (:file "protocol")
                 (:file "generators")
                 (:file "conditions")
                 (:file "runner")))))

(asdf:defsystem #:cl-hegel/tests
  :depends-on (#:cl-hegel #:fiveam)
  :serial t
  :components ((:module "t"
                :components
                ((:file "package")
                 (:file "packet-test")
                 (:file "connection-test")
                 (:file "protocol-test")
                 (:file "generators-test")
                 (:file "conditions-test")
                 (:file "runner-test")
                 (:file "integration-test")))))
