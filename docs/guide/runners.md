# Runners

A runner is another machine that runs jobs for your engine: a Linux box for Android and Flutter
builds, another Mac for iOS signing. It dials out to the engine, so nothing on the runner needs an
open port. This guide is the setup from the owner's side; [the reference](../reference/runners.md)
has the protocol and the details.

## Pair a runner

1. Tell the engine the address runners reach it at, the **runner URL**:

   ```sh
   xp runners url https://mac.tailnet.ts.net
   ```

   The app has the same field in Settings, Runners. Every pairing command carries it. Without one,
   the pairing command names the address the CLI or the app reaches the engine at, which is
   usually `http://127.0.0.1:7480`: that address only works on the engine's own machine.
   [Reaching the engine](#reaching-the-engine) says how to get an address another machine can use.

2. Make a pairing token on the engine (or with Pair runner in the app):

   ```sh
   xp runners pair aws-builder
   ```

   It prints the whole command for the runner, which works once, within 15 minutes:

   ```text
   On the runner machine, within 15 minutes:
     xp runner pair --engine https://mac.tailnet.ts.net --token xpp_...
   ```

3. On the runner, run that command, then `xp runner start`, or `xp runner install-service` to keep
   it running.

Runners paired already keep the address they were paired with (it is in their `runner.json`). After
you change the runner URL, for example when you move from an SSH tunnel to Tailscale, pair each
runner again: `xp runners pair <name>` on the engine, then the printed `xp runner pair` on the
runner, which replaces its old credential.

## Set up a Linux runner

On Debian or Ubuntu, one command installs `xp` and everything `android` and `flutter` jobs need: a
JDK 17, git, ssh, curl, unzip, xz, zip, perl and the Android SDK.

```sh
curl -fsSL https://xpath.abdurahman.ly/install | sh -s -- --runner --with-android
```

It ends with the three next steps: `xp runner doctor` (what this runner offers, and why not the
rest), the pairing command, and `xp runner install-service`.

## The runner image

`ghcr.io/abdurahmanalmehdi/xpath-runner` is a runner that builds Android and Flutter apps out of the
box (amd64 only: Google ships no Android build tools for Linux arm64). Flutter is not in the image:
the runner fetches the version each project pins into its volume, so one image serves every
Flutter version and the volume caches them.

```sh
docker volume create xpath-runner
docker run --rm -it -v xpath-runner:/data ghcr.io/abdurahmanalmehdi/xpath-runner \
  runner pair --engine https://mac.tailnet.ts.net --token xpp_...
docker run --rm -v xpath-runner:/data ghcr.io/abdurahmanalmehdi/xpath-runner runner doctor
docker run -d --name xpath-runner --restart on-failure -v xpath-runner:/data \
  ghcr.io/abdurahmanalmehdi/xpath-runner
```

- Everything the runner keeps is in the volume, its home folder (`/data/home`) included, so its
  SSH key and its Gradle caches survive a new container.
- The runner fetches the source with its own SSH key. Make one in the volume and add the public
  key (`doctor` prints its path) as a deploy key of the repository (an access key on Bitbucket):
  `docker exec xpath-runner ssh-keygen -t ed25519`. Or mount a key read-only. SSH records the host
  key of the git server the first time; a key that changes later fails the job.
- When the runner updates itself to its engine's version, the update survives a restart of the
  container. A runner the engine revoked, that another connection replaced, or that is not paired
  exits with 0 and says why, so `--restart on-failure` does not start it again.

## Linux iOS

Experimental, and opt-in per runner (ADR 0014): a Linux runner can build, sign and hand back iOS
apps through [omarchy-apple-dev](https://github.com/joshuaswarren/omarchy-apple-dev), so a release
with iOS needs no Mac, setup included. Macs keep working as before, and are preferred when both
are free.

**What you supply.** XPath never downloads, bundles or redistributes Apple software. Download
`Xcode.xip` yourself, in a browser on any machine, from Apple's developer site. Using the Xcode SDK
on hardware that is not Apple's is likely outside Apple's SDK agreement: that question is yours,
not XPath's. omarchy-apple-dev is tested on Arch Linux (Omarchy), x86_64 and arm64.

1. Check out omarchy-apple-dev at the commit this XPath pins. `xp runner doctor` prints it; until
   upstream merges the fixes XPath needs, it is the `xpath/pin` branch of a fork:

   ```sh
   git clone https://github.com/AbdurahmanAlmehdi/omarchy-apple-dev ~/omarchy-apple-dev
   git -C ~/omarchy-apple-dev checkout <the commit xp runner doctor names>
   ```

2. Run its `install-toolchain.sh` with your `Xcode.xip`, as the user the runner runs as. It
   installs Swift, rcodesign, the LLVM tools and the pymobile3 python, and cuts the darwin SDK
   bundle from the `.xip`.
3. Set `XP_IOS_LINUX_DIR` to the checkout before you start or install the runner, so the service
   keeps it:

   ```sh
   export XP_IOS_LINUX_DIR=~/omarchy-apple-dev
   xp runner doctor             # ios-linux, or each missing piece with its fix
   xp runner install-service
   ```

   Each Flutter version needs about 7 GB more for its own install, which the first iOS job of that
   version prepares (`flutter/setup.sh`, a few minutes). Installs no job used for 30 days are
   deleted.

**Signing without a Mac.** The flavor needs an App Store Connect API key (`asc_key`) and an Apple
Distribution identity. The engine creates the identity with the key:

```sh
xp credentials add --kind asc_key --name "ASC" --key-id ... --issuer-id ... --p8 AuthKey.p8
xp credentials assign "ASC" --project acme/app --flavor prod
xp credentials add --kind apple-distribution --name "Linux signing" --create \
  --project acme/app --flavor prod
```

Apple allows a team three distribution certificates; at the limit the engine refuses and lists
them, so you can revoke one in App Store Connect. You can also import an identity you have:
`--private-key key.pem --certificate cert.cer` (from a `.p12`: `openssl pkcs12 -in id.p12 -nodes
-nocerts` gives the key, `-clcerts -nokeys` the certificate). The engine makes the App Store profile
for each build with the API key; the runner gets the identity and the profile for the job only, in
its tmpfs secret folder, and never the API key. Runners never create certificates.

**What still needs a Mac.** The scan says "Needs a Mac for iOS" with the reasons, the dry run shows
them, and such a job waits for a Mac: Flutter flavors, an entry point other than `lib/main.dart`,
Shorebird iOS, debug and profile builds, app extensions, plugins that build with CocoaPods (enable
Swift Package Manager), storyboards beyond Flutter's template, Flutter older than 3.47, and the
`ios.stripAndReexport` step. There is no iOS Simulator on Linux: iOS device tests and screenshots
are not offered there; run them on an Android emulator, or on a Mac.

## When the engine is away

A runner may be cut off from the engine for hours: the engine's Mac sleeps, the tunnel drops, the
network changes. Nothing needs restarting.

- **The runner keeps trying.** It reconnects with a growing delay, at most 60 seconds between
  attempts, and comes back within about a minute of the engine. Its log stays short: one line when
  the connection is lost, one for the first failed attempt, then one every 10 minutes ("The engine
  has been unreachable for 2 h 10 min; still trying every 60 s"), and one when it is back
  ("Connected again after 3 h 12 min").
- **A job it holds is stopped once its lease runs out.** A lease lasts 90 seconds after the last
  heartbeat the engine acknowledged. When 90 seconds and 15 more have passed without one, the
  engine has given the job up, so the runner stops it as a cancel would: its processes end, its
  secrets are wiped, and nothing more is reported. The runner says `Lost the lease of job <id>
  while the engine was unreachable; stopped it.`
- **The engine decides what happens to the job.** It is queued again, or, when the step that was
  running has a side effect (an upload, a push, a Shorebird release), it waits for you to resume it
  and is never repeated by itself.

So keep the engine's Mac awake while runners have work: a Mac that sleeps in the middle of a build
loses the build. A Mac mini that never sleeps is the setup the plan assumes (D-10); a laptop engine
is your call.

## Reaching the engine

The engine listens on `127.0.0.1:7480`, so only its own machine reaches it. A runner on another
machine needs an address that leads there. Pick one of these three; Tailscale is the one we
recommend. The commands follow the Tailscale Serve syntax of Tailscale 1.52 and later, checked
against Tailscale's docs in October 2026.

### Tailscale (recommended)

Tailscale puts the engine's Mac and the runner on one private network (a tailnet). `tailscale
serve` then publishes the engine at `https://<mac>.<tailnet>.ts.net` with a real certificate.
The engine keeps listening on loopback, nothing is public, and the runner's traffic is encrypted
twice (TLS inside WireGuard). WebSockets, which runners use, pass through.

1. Install Tailscale on the engine's Mac and on the runner, and sign both in to the same tailnet.
   On a Linux runner:

   ```sh
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   ```

2. In the Tailscale admin console, under DNS, turn on MagicDNS and HTTPS Certificates. Serve
   needs them; if they are off, `tailscale serve` offers to turn them on.

3. On the engine's Mac, publish the engine. `--bg` keeps it published after the terminal closes
   and across restarts:

   ```sh
   tailscale serve --bg http://127.0.0.1:7480
   tailscale serve status        # prints https://<mac>.<tailnet>.ts.net
   ```

4. Tell the engine that address, so pairing commands carry it:

   ```sh
   xp runners url https://<mac>.<tailnet>.ts.net
   ```

5. Pair the runner as in [Pair a runner](#pair-a-runner). To stop publishing the engine later:
   `tailscale serve --https=443 http://127.0.0.1:7480 off`.

### Cloudflare Tunnel

`cloudflared` on the engine's machine maps a hostname of a domain you have on Cloudflare to the
engine. The engine becomes reachable from the internet, protected by its bearer tokens (every
route but `/health` and `/version` needs one).

```sh
cloudflared tunnel login
cloudflared tunnel create xpath
cloudflared tunnel route dns xpath xpath.example.com
cloudflared tunnel run --url http://127.0.0.1:7480 xpath
xp runners url https://xpath.example.com
```

Cloudflare Access in front of the tunnel is **not** supported yet: the runner cannot send Access
service-token headers, so Access would turn it away.

### SSH reverse tunnel

When the engine's Mac can reach the runner over SSH, a reverse tunnel gives the runner the engine
on its own loopback. SSH encrypts the traffic. It takes one tunnel per runner, kept up by
`autossh`:

```sh
autossh -M 0 -N -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes -R 127.0.0.1:7480:127.0.0.1:7480 user@runner
```

On the runner the engine is then `http://127.0.0.1:7480`, so pair it with that address (`xp runners
url http://127.0.0.1:7480`, or the pairing command as printed). To keep the tunnel up on the Mac,
save this LaunchAgent as `~/Library/LaunchAgents/ly.abdurahman.xpath.tunnel.plist`, with your
user, runner and the path of `autossh` (`which autossh`), then `launchctl load` it. XPath does not
ship or install it.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>ly.abdurahman.xpath.tunnel</string>
  <key>ProgramArguments</key>
  <array>
    <string>/opt/homebrew/bin/autossh</string>
    <string>-M</string><string>0</string>
    <string>-N</string>
    <string>-o</string><string>ServerAliveInterval=30</string>
    <string>-o</string><string>ExitOnForwardFailure=yes</string>
    <string>-R</string><string>127.0.0.1:7480:127.0.0.1:7480</string>
    <string>USER@RUNNER</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
```

### What not to do

Do not start the engine with `--host 0.0.0.0` and send runners to it over plain `http`. The runner
connection carries signing material (keystores, certificates, API keys) for the jobs it runs, and
anyone on the path could read it. `xp runners url` warns when a plain `http` address leaves the
machine and the tailnet.
