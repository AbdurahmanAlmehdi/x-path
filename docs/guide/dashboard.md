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
to a server, and the dashboard takes it out of the address at once.

### The first admin of a new engine

An engine without the Mac app (a Linux bundle or the Docker image) starts with no one who can sign
in. On the engine's machine, as the user that runs `xpd`:

```sh
xpd person create --name Sam --role admin   # prints the id, and the sign-in code on stderr
xpd person code Sam                         # a new code, when that one has expired
```

Then open `http://127.0.0.1:7480` on that machine and enter the code. An engine upgraded from an
earlier version already has one admin, `Owner`, who owns every token the engine had.

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

## Open the dashboard from another machine

The engine has no TLS of its own, and a sign-in cookie must not cross a network in the clear. So a
browser signs in only:

- on the engine's own machine, at `http://127.0.0.1:7480` or `http://localhost:7480`; or
- through the engine's **public URL**: an `https://` address of a proxy in front of the engine.

A browser on another machine that opens `http://<engine-ip>:7480` gets the sign-in page, but the
sign-in is refused with the reason: "A browser signs in only on the engine machine, or through
the engine's HTTPS public URL".

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

Then set the public URL, as an admin:

```sh
xp settings public-url https://xpath.example.com
xp settings public-url --clear       # back to the engine machine only
```

Through the public URL the session cookie is `__Host-xp_session`, sent only over HTTPS; on the
engine's own machine it is `xp_session`. The public URL is the one address, besides the engine's
own, that the engine accepts a browser from: a page of any other site cannot use your session.

The public URL and the runner URL (`xp runners url`) are separate settings. They can be the same
address when runners reach the engine through the same proxy.
