;;;; link-dapla-deploy.asd

(asdf:defsystem :link-dapla-deploy)

(asdf:defsystem :link-dapla-deploy/deploy
  :description "Roswell/Consfigurator deploy of SearXNG on rootless Podman
quadlets behind HAProxy at find.dapla.net."
  :license "BSD-3-Clause"
  :depends-on (:cl-inix :consfigurator)
  :components ((:file "src/deploy"))
  :in-order-to ((asdf:test-op (asdf:test-op :link-dapla-deploy/e2e))))

(asdf:defsystem :link-dapla-deploy/docs
  :depends-on (:link-dapla-deploy/deploy :40ants-doc :40ants-doc-full)
  :components ((:file "src/docs")))

(asdf:defsystem :link-dapla-deploy/e2e
  :depends-on (:link-dapla-deploy/deploy :fiveam :dexador)
  :components ((:file "t/e2e"))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :fiveam :run! :link-dapla-deploy-e2e)))
