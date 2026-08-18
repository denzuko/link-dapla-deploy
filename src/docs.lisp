;;;; src/docs.lisp -- link-dapla-deploy/docs

(defpackage :link-dapla-deploy/docs
  (:use :cl)
  (:import-from :40ants-doc :defsection))

(in-package :link-dapla-deploy/docs)

(defsection @link-dapla-deploy (:title "link-dapla-deploy")
  "Roswell/Consfigurator deploy for link.dapla.net."
  (@deploy-properties section))

(defsection @deploy-properties (:title "Consfigurator Properties")
  (link-dapla-deploy/deploy:deploy-app function))
