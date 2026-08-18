(:repo-name    'link-dapla-deploy'
 :system-name  'link-dapla-deploy'
 :fqdn         'link.dapla.net'
 :vhost-name   'link'
 :service-user 'chhoto'
 :description  'Chhoto URL shortener'
 :image        'oci.dapla.net/sintan1729/chhoto-url:latest'
 :internal-port 4567
 :health-path  '/'
 :extra-envs ('CHHOTO_URL_SITE_URL=https://link.dapla.net'
               'CHHOTO_URL_REDIRECT_METHOD=PERMANENT')
 :datasets
 (  (:name 'users/chhoto'
   :mountpoint '/var/lib/chhoto'
   :purpose 'Service account home directory')
  (:name 'containers/chhoto'
   :mountpoint '/srv/chhoto'
   :purpose 'Chhoto SQLite database'))
)
