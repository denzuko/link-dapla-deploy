;;;; src/deploy.lisp -- link-dapla-deploy/deploy core package
;;;;
;;;; Consfigurator properties and DEFHOST for Chhoto URL shortener at
;;;; link.dapla.net. Chhoto is a minimal, self-hosted URL shortener backed
;;;; by a SQLite database stored on the ZFS data dataset.

(defpackage :link-dapla-deploy/deploy
  (:use :cl)
  (:import-from :consfigurator
                :defprop :defhost :mrun :stripln
                :remote-exists-p :write-remote-file :on-change)
  (:import-from :consfigurator.property.file
                :has-content :containing-directory-exists)
  (:import-from :consfigurator.property.systemd :lingering-enabled)
  (:import-from :consfigurator.property.service :reloaded)
  (:export :*service-user* :*home-dataset* :*home-mountpoint*
           :*data-dataset* :*data-mountpoint*
           :*home-dataset-keyfile* :*data-dataset-keyfile*
           :*haproxy-fqdn*
           :deploy-app
           :zfs-encryption-key :zfs-dataset-mounted
           :rootless-service-account
           :images-pulled :quadlets-activated
           :cinix-write-string
           :service-account-uid
           :quadlets-written
           :haproxy-vhost-written
           :link-network-sections
           :link-container-sections
           :haproxy-vhost-config))

(in-package :link-dapla-deploy/deploy)

(defparameter *service-user* "chhoto")
(defparameter *home-dataset* "storage/users/chhoto")
(defparameter *home-mountpoint* "/var/lib/chhoto")
(defparameter *home-dataset-keyfile* "/etc/zfs-keys/chhoto-users.key")
(defparameter *data-dataset* "storage/containers/chhoto")
(defparameter *data-mountpoint* "/srv/chhoto"
  "Chhoto data directory: SQLite database for shortened links.")
(defparameter *data-dataset-keyfile* "/etc/zfs-keys/chhoto-data.key")
(defparameter *haproxy-fqdn* "link.dapla.net")
(defparameter *haproxy-vhost-name* "link")

(defprop zfs-encryption-key :posix (path)
  "Generate a raw 32-byte ZFS encryption key at PATH, once, left alone on redeploy."
  (:desc (format nil "ZFS encryption key at ~A" path))
  (:check (remote-exists-p path))
  (:apply
   (containing-directory-exists path)
   (write-remote-file path (mrun "openssl" "rand" "32") :mode #o600)))

(defun zfs-create-command (dataset mountpoint keyfile)
  (if keyfile
      (format nil "zfs create -o mountpoint=~A -o encryption=aes-256-gcm -o keyformat=raw -o keylocation=file://~A ~A"
              mountpoint keyfile dataset)
      (format nil "zfs create -o mountpoint=~A ~A" mountpoint dataset)))

(defprop zfs-dataset-mounted :posix (dataset mountpoint &optional keyfile)
  "Ensure DATASET exists, mounted at MOUNTPOINT, AES-256-GCM encrypted when KEYFILE is supplied."
  (:desc (format nil "ZFS dataset ~A mounted at ~A~:[~; (encrypted)~]" dataset mountpoint keyfile))
  (:check
   (multiple-value-bind (out err exit)
       (consfigurator:run :may-fail (format nil "zfs get -H -o value mounted ~A" dataset))
     (declare (ignore err))
     (and (zerop exit) (string= "yes" (stripln out)))))
  (:apply
   (if (zerop (mrun :for-exit (format nil "zfs list -H -o name ~A" dataset)))
       (progn (when keyfile (mrun (format nil "zfs load-key ~A" dataset)))
              (mrun (format nil "zfs mount ~A" dataset)))
       (mrun (zfs-create-command dataset mountpoint keyfile)))))

(defprop rootless-service-account :posix (username home)
  "Ensure system account USERNAME exists with home HOME, without creating the directory."
  (:desc (format nil "System account ~A at ~A" username home))
  (:check (zerop (mrun :for-exit "id" username)))
  (:apply (mrun "useradd" "--system" "--no-create-home" "--home-dir" home username)))

(defprop images-pulled :posix (user &rest images)
  "Pull IMAGES into USER's rootless Podman image store via `machinectl shell`."
  (:desc (format nil "Podman images pulled for ~A" user))
  (:check (every (lambda (i) (zerop (mrun :for-exit (format nil "machinectl shell ~A@ /usr/bin/podman image exists ~A" user i)))) images))
  (:apply (dolist (i images) (mrun (format nil "machinectl shell ~A@ /usr/bin/podman pull ~A" user i)))))

(defun cinix-write-string (sections)
  "Serialize an alist of (section-name . ((key . value) ...)) into INI/systemd unit-file text."
  (with-output-to-string (s)
    (dolist (section sections)
      (format s "[~A]~%" (car section))
      (dolist (kv (cdr section)) (format s "~A=~A~%" (car kv) (cdr kv)))
      (format s "~%"))))

(defun service-account-uid (username)
  "Read USERNAME's UID via getent at apply time. The UID is the loopback PublishPort."
  (parse-integer
   (third (uiop:split-string
           (string-trim '(#\Newline #\Space)
             (with-output-to-string (s)
               (uiop:run-program (list "getent" "passwd" username) :output s)))
           :separator '(#\:)))))

(defun link-network-sections ()
  '(("Network" . (("NetworkName" . "link") ("Internal" . "true")))))

(defun link-container-sections (data-mountpoint)
  "Cinix AST for link.container. The loopback port is the service account UID.
   CHHOTO_URL_SITE_URL must match the public-facing domain so generated short
   links resolve correctly. CHHOTO_URL_REDIRECT_METHOD is PERMANENT so clients
   cache the redirect."
  (let ((port (service-account-uid *service-user*)))
    `(("Unit"      . (("Description" . "Chhoto URL shortener")))
      ("Container" . (("Image"         . "oci.dapla.net/sintan1729/chhoto-url:latest")
                      ("ContainerName" . "chhoto")
                      ("AutoUpdate"    . "registry")
                      ("PublishPort"   . ,(format nil "127.0.0.1:~A:4567" port))
                      ("Volume"        . ,(format nil "~A:/app/urls.sqlite:Z" data-mountpoint))
                      ("Environment"   . "CHHOTO_URL_SITE_URL=https://link.dapla.net")
                      ("Environment"   . "CHHOTO_URL_REDIRECT_METHOD=PERMANENT")
                      ("Network"       . "link.network")
                      ("Label"         . "io.containers.autoupdate=registry")))
      ("Service"   . (("Restart" . "on-failure") ("TimeoutStartSec" . "60") ("TimeoutStopSec" . "30")))
      ("Install"   . (("WantedBy" . "default.target"))))))

(defun haproxy-vhost-config ()
  "HAProxy vhost for link.dapla.net. Redirect responses from the backend are
   passed through unmodified so PERMANENT redirects reach the client intact.
   Backend port is the service account UID."
  (let ((port (service-account-uid *service-user*)))
    (format nil
"frontend link_http
  bind *:80
  acl host_link hdr(host) -i link.dapla.net
  redirect scheme https code 301 if host_link

frontend link_https
  bind *:443 ssl crt /etc/haproxy/certs/link.dapla.net.pem alpn h2,http/1.1
  acl host_link hdr(host) -i link.dapla.net
  http-response set-header Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\"
  http-response set-header X-Content-Type-Options nosniff
  http-response set-header Referrer-Policy no-referrer
  http-response set-header Permissions-Policy \"interest-cohort=()\"
  use_backend link_be if host_link

backend link_be
  balance roundrobin
  option httpchk GET /
  http-check expect status 200
  timeout connect 5s
  timeout server  10s
  server chhoto 127.0.0.1:~A check inter 10s rise 2 fall 3
" port)))

(defprop quadlets-activated :posix (user)
  "Reload USER's user-scope systemd daemon and restart chhoto."
  (:desc (format nil "Quadlets activated for ~A" user))
  (:apply
   (mrun (format nil "machinectl shell ~A@ /usr/bin/systemctl --user daemon-reload" user))
   (mrun (format nil "machinectl shell ~A@ /usr/bin/systemctl --user restart chhoto" user))))


(defprop quadlets-written :posix (user home data-mountpoint)
  "Write all chhoto quadlet unit files into USER's systemd container
   directory. The service account UID is read at apply time via getent,
   after ROOTLESS-SERVICE-ACCOUNT has run, so PublishPort is always correct."
  (:desc (format nil "Chhoto quadlet units written for ~A" user))
  (:apply
   (let ((quadlet-dir (format nil "~A/.config/containers/systemd" home)))
     (consfigurator.property.file:containing-directory-exists
      (format nil "~A/link.network" quadlet-dir))
     (write-remote-file
      (format nil "~A/link.network" quadlet-dir)
      (cinix-write-string (link-network-sections)))
     (write-remote-file
      (format nil "~A/link.container" quadlet-dir)
      (cinix-write-string (link-container-sections data-mountpoint))))))


(defprop haproxy-vhost-written :posix ()
  "Write the HAProxy vhost config for this service. Skipped when the
   service account does not yet exist, since the port cannot be determined.
   Reloads HAProxy only when content changes."
  (:desc (format nil "HAProxy vhost written for ~A" *haproxy-fqdn*))
  (:check (null (service-account-uid *service-user*)))
  (:apply
   (let ((port (service-account-uid *service-user*)))
     (unless port
       (consfigurator:inapplicable-property
        "Service account ~A does not exist; cannot determine port."
        *service-user*))
     (let* ((cfg-path (format nil "/etc/haproxy/conf.d/~A.cfg" *haproxy-vhost-name*))
            (new-content (haproxy-vhost-config))
            (current (when (probe-file cfg-path)
                       (uiop:read-file-string cfg-path))))
       (unless (equal new-content current)
         (containing-directory-exists cfg-path)
         (write-remote-file cfg-path new-content)
         (consfigurator.property.service:reloaded "haproxy"))))))

(defhost link-host (:deploy (:local))
  "The Chhoto URL shortener host: two AES-256-GCM ZFS datasets, rootless
   service account, linger, pulled image, quadlet unit, and HAProxy vhost."
  (zfs-encryption-key *home-dataset-keyfile*)
  (zfs-encryption-key *data-dataset-keyfile*)
  (zfs-dataset-mounted *home-dataset* *home-mountpoint* *home-dataset-keyfile*)
  (zfs-dataset-mounted *data-dataset* *data-mountpoint* *data-dataset-keyfile*)
  (rootless-service-account *service-user* *home-mountpoint*)
  (lingering-enabled *service-user*)
  (images-pulled *service-user* "oci.dapla.net/sintan1729/chhoto-url:latest")
  (quadlets-written *service-user* *home-mountpoint* *data-mountpoint*)
  (quadlets-activated *service-user*)
  (haproxy-vhost-written))

(defun deploy-app ()
  "Provision Chhoto via LINK-HOST. Aborts loudly if any property is skipped."
  (format t "~&--> Provisioning via Consfigurator (LINK-HOST)...~%")
  (let ((provisioning-failed nil))
    (handler-bind ((consfigurator::skipped-properties
                     (lambda (c) (declare (ignore c)) (setf provisioning-failed t))))
      (link-host))
    (when provisioning-failed
      (error "LINK-HOST provisioning reported failed properties. Refusing to proceed.")))
  (format t "~&--> Chhoto provisioned. Visit https://~A~%" *haproxy-fqdn*))
