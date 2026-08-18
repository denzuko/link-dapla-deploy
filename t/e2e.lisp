;;;; t/e2e.lisp -- link-dapla-deploy/e2e

(defpackage :link-dapla-deploy/e2e
  (:use :cl :fiveam)
  (:import-from :link-dapla-deploy/deploy :*haproxy-fqdn*)
  (:export :run-e2e))

(in-package :link-dapla-deploy/e2e)

(def-suite :link-dapla-deploy-e2e
  :description "Smoke tests for link.dapla.net.")

(in-suite :link-dapla-deploy-e2e)

(test http-redirect
  "Plain HTTP requests redirect to HTTPS."
  (multiple-value-bind (body status)
      (dex:get (format nil "http://~A/" *haproxy-fqdn*)
               :force-string t :want-stream nil :redirect nil)
    (declare (ignore body))
    (is (member status '(301 302)))))

(test frontend-responds
  "The service frontend returns HTTP 200."
  (multiple-value-bind (body status)
      (dex:get (format nil "https://~A" *haproxy-fqdn*)
               :force-string t :want-stream nil)
    (declare (ignore body))
    (is (= 200 status))))

(defun run-e2e ()
  "Run the post-deploy e2e suite and signal an error if any test fails."
  (let ((results (run :link-dapla-deploy-e2e)))
    (unless (every #'fiveam::test-passed-p results)
      (error "link-dapla-deploy e2e suite: one or more tests failed."))))
