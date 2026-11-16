# The web dashboard

The engine serves a web dashboard on its own address: the projects, the runs, dispatching a
workflow and the live log of a job, in any browser. It is how a team on a Linux engine gets a GUI,
and how people other than the owner use XPath. Every page shows only what your role allows, and
the engine checks every request again.

## Sign in

There are no passwords. You sign in with a one-time sign-in code: 16 letters and digits, shown as
`XXXX-XXXX-XXXX-XXXX`. A code works once, for 10 minutes. A browser stays signed in for 8 hours,
then asks for a new code. Sign out from the top bar.

- **On the Mac app:** Settings, Web dashboard, Open dashboard. The browser opens signed in as you.
- **From the terminal:** `xp dashboard` does the same. `xp dashboard --print` prints the link
  instead of opening it.
- **With a code an admin gave you:** open the engine's address and enter the code on the sign-in
  page.

The link the app and `xp dashboard` open carries the code after `#`, which the browser never sends
to a server, and the dashboard takes it out of the address at once. To open it, they pass the link
to `open` (macOS) or `xdg-open` (Linux) as an argument, so for that moment the code is in the
machine's process list. That is the one place XPath puts a secret in a process argument, on
purpose: the code works once, expires in 10 minutes, and the browser uses it within seconds. On a
shared machine, `xp dashboard --print` keeps it out of the process list.

### The first admin of a new engine

An engine without the Mac app (a Linux bundle or the Docker image) starts with one admin, `Owner`,
and no sign-in code, so no one can sign in yet. On a server, put the [proxy](#behind-a-proxy) in
front of the engine first. Then, on the engine's machine, as the user that runs `xpd`:

```sh
xpd settings public-url https://<machine>.<tailnet>.ts.net
xpd person create --name Sam --role admin   # prints the id, and the code and a sign-in link on stderr
xpd person code Sam                         # a new code and link, when that one has expired
```

Open the link from any device that reaches the public URL: it signs you in. Like `xpd person`,
`xpd settings public-url` needs no token, and a running engine uses the new URL at once.

Without a public URL the commands print the code only. Enter it on the sign-in page:

- **On the engine machine,** when it has a desktop: open `http://127.0.0.1:7480` and enter the
  code.
- **Through an SSH tunnel,** for a server without a browser or a proxy. On your own machine:

  ```sh
  ssh -N -L 7480:127.0.0.1:7480 you@server
  ```

  Then open `http://localhost:7480` there and enter the code. Keep the local port the same as the
  engine's: the engine accepts a browser on the address of its own port only, so a tunnel from
  another local port is refused.

`xpd person code Owner` gives a code for `Owner` instead. An engine upgraded from an earlier
version has `Owner` too, who owns every token the engine had.

In Docker, run them with `docker exec xpath xpd person ...`. The engine in the container sees a
browser on the host come from Docker's network, not from its own machine, so a Docker engine's
dashboard needs the [proxy](#behind-a-proxy) even on the same machine.

## Roles

Each person has one role. A role includes everything the roles before it may do.

| Role | May |
|---|---|
| `viewer` | See every project, run, job, log, release and approval. Never a secret's value. |
| `developer` | Dispatch workflows, run again, cancel and resume jobs, add, update and scan projects, edit workflows, pin artifacts, and ask for the gated release actions (a new build, a merge, a rollout change, a patch move), whose approval needs a releaser. |
| `releaser` | Approve or deny gates, abandon a release, set its notes, store texts and store status, and turn a gate on. |
| `admin` | Manage people, sign-in codes and everyone's tokens, credentials, runners, storage, the GitHub token and the public URL; remove projects, and turn a gate off. |

A viewer sees no Dispatch button and no Cancel or Run again. A role change applies to the next
request; a person who is removed, or whose sign-in is revoked, is signed out at once, in every tab.

## Dispatch and follow a run

1. Open **Projects** and pick a project. Its page shows the apps and their flavors, and the newest
   runs.
2. **Dispatch…** (developers and up) opens the form: the workflow, the app, the flavors and
   platforms, the ref, the version and the workflow's inputs. It starts with the inputs of the
   workflow's last run. Below the form, the engine's plan says which jobs would run where, which
   gates they would stop at, and what is left out and why.
3. **Dispatch** starts the run and opens its page: its state, who started it, and its jobs by
   stage. The page follows the engine, so states change on their own.
4. Pick a job to see its steps and its log. The log follows the job live; scroll up to read and it
   stops following, **Follow** goes back to the end. The text can be selected and copied. If the
   connection drops, the log carries on from the last line it showed, without repeating a line.

**Runs** lists the runs of every project, newest first. The project, workflow and state filters
are in the address, so a filtered list can be bookmarked or shared.

## Approve a gate, follow a release

**Approvals** shows how many gates wait next to its name. Pick one to see what it is bound to (the
project, flavor, version, commit and the job that waits) and what approving does. **Approve…**
and **Deny…** (releasers and up) open the review: Approve works a moment after it opens, and
Return never approves; ⌘↩ or Ctrl+↩ does. The first decision counts: if someone decided first, or
the approval expired, the review says who and how. The approval records your name, and the inbox
moves to Decided, so it stays in view.

A project's **Releases** shows each production release with its App Store and Google Play lanes,
its timeline, release notes, store texts, pull request and Shorebird patches. **Refresh** asks the
stores at once. **Merge**, a new build of a rejected version, the rollout buttons and the patch
moves (developers and up) each start a run that waits for a releaser's approval. Marking a store
by hand and saving the store texts need a releaser. A project's
**Tests** shows a test run against its baseline, new failures first; a job that ran tests links to
its results.

## Open the dashboard from another machine

The engine has no TLS of its own, and a sign-in cookie must not cross a network in the clear. So a
browser signs in only:

- on the engine's own machine, at `http://127.0.0.1:7480` or `http://localhost:7480`; or
- through the engine's **public URL**: an `https://` address of a proxy in front of the engine.

An engine started with `xpd serve --host` on an address other machines reach serves them the
sign-in page at `http://<engine-ip>:7480`, but it refuses the sign-in with the reason and the fix:
"A browser signs in only on the engine machine, or through the engine's HTTPS public URL", and to
put an HTTPS proxy in front of the engine and set its address as the public URL.

### Behind a proxy

Put an HTTPS proxy in front of the engine, then tell the engine its address. Any proxy that passes
WebSockets and the `Origin` header through works; these two are the shortest.

**Caddy**, on a machine with a domain name that points to it. Caddy gets the certificate by
itself. In the `Caddyfile`:

```text
xpath.example.com {
	reverse_proxy 127.0.0.1:7480
}
```

**Tailscale**, for a dashboard only your tailnet reaches (see
[Reaching the engine](runners.md#reaching-the-engine) for the setup):

```sh
tailscale serve --bg http://127.0.0.1:7480
tailscale serve status        # prints https://<machine>.<tailnet>.ts.net
```

A proxy on the engine machine must pass the browser's `Host` on (nginx: `proxy_set_header Host
$host;`; Caddy and `tailscale serve` do by default). One that rewrites `Host` to
`127.0.0.1:<port>` makes the engine treat public visitors as loopback and give them the cookie
without `Secure`.

Then set the public URL, as an admin, or on the engine machine with `xpd settings public-url`,
which needs no token:

```sh
xp settings public-url https://xpath.example.com
xp settings public-url --clear       # back to the engine machine only
```

Through the public URL the session cookie is `__Host-xp_session`, sent only over HTTPS; on the
engine's own machine it is `xp_session_<port>` (for example `xp_session_7480`), named after the
engine's port so two engines on one machine keep separate sessions. The public URL is the one address, besides the engine's
own, that the engine accepts a browser from: a page of any other site cannot use your session.

The public URL and the runner URL (`xp runners url`) are separate settings. They can be the same
address when runners reach the engine through the same proxy.
