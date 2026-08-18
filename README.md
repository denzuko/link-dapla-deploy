# link-dapla-deploy

Roswell/Consfigurator deploy of the service at `link.dapla.net`.

## Repository Layout

```
link-dapla-deploy.ros   Thin Roswell entry point
link-dapla-deploy.asd   Umbrella ASDF system definition
qlfile         Qlot dependency pins
src/deploy.lisp  Consfigurator properties and DEFHOST
src/docs.lisp    40ants-doc sections
t/e2e.lisp       Post-deploy FiveAM smoke tests
docs.ros         Documentation generator
Makefile         build / test / doc / dist / clean
```

## Installation

```sh
ros install qlot
qlot install
./link-dapla-deploy.ros
```

## Runbook

```sh
machinectl shell link@ -- systemctl --user status
machinectl shell link@ -- journalctl --user -f
machinectl shell link@ -- podman auto-update
```

Redeploy by re-running `./link-dapla-deploy.ros`. Idempotent.

## Playbook

### ZFS replication (rsync.net)

```sh
zfs snapshot storage/containers/link@$(date +%Y%m%d)
zfs send -w storage/containers/link@$(date +%Y%m%d) | \
  ssh user@rsync.net zfs receive backup/link
```

Key files under `/etc/zfs-keys/` must be backed up separately.

## Decommission

```sh
machinectl shell link@ -- systemctl --user stop link
machinectl shell link@ -- systemctl --user disable link
zfs destroy -r storage/users/link
zfs destroy -r storage/containers/link
```

## License

BSD 3-Clause. See [LICENSE](LICENSE).
