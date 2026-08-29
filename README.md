This repo contains configuration files that I use for Linux

## Layout

Each top-level directory is a GNU Stow package holding paths relative to
`$HOME`. `_shell` is the only one that targets `$HOME` directly; the rest
map into `~/.config/<app>`.

## Deploying

```sh
stow -t ~ hypr voxtype     # a few packages
stow -t ~ */               # everything
stow -D -t ~ wleave        # remove one
```

`systemd` deliberately does not link `~/.config/systemd` as a whole, since
that directory also holds units this repo does not track. Stow descends and
links only `user/voxtype.service.d`.
