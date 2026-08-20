---
area: clients/visionOS
status: blocked
depends_on: []
blocks: []
updated: 2026-08-20
---

# Reaching a house from outside its network

Today the headset and the house have to be on the same local network. Leave the
flat and Hearth is a client with nothing to connect to.

## Why this file is in clients/visionOS and does not belong to it

It is a client-wide problem: the phone has the same limitation and
[wiki/clients/ios.md](../../../wiki/clients/ios.md) lists it too. It sits here
because the visionOS article names it as a limitation and a backlog that omits
its own stated limitations is a backlog that lies.

**The work is almost entirely not in this client.** Whatever answers this
answers it for every client at once, and the visionOS side is likely to be
"nothing, once the transport exists" -- `ServerConfig` takes a host and a port,
and a tailnet address is a host.

## What is already known

Tailscale is the intended shape and has been mentioned since the earliest
planning. It fits the product's actual claim -- there is no cloud account and no
third party between you and your house -- in a way that a hosted relay would
not. A tailnet address behaves like a LAN address to everything above it, which
is why the client side may genuinely be free.

Pairing does not need to change. The token model was built for exactly this: a
long random token, hashed on the house, sent with every request, no expiry, one
revocation to cut a lost device off. It does not care which network the request
arrived on.

**But one thing does need to change**, and it is the reason this is `blocked`
rather than `open`: the pairing-management routes deliberately answer only from
the house's own machine (127.0.0.1), so a stolen paired device cannot pair its
thief's headset or revoke yours. That rule was written when "not local" meant
"not trusted." A tailnet makes a third category -- not local, but not the open
internet either -- and somebody has to decide whether it counts.

## A trap already recorded

Turning Wi-Fi off to test the tailnet path makes an Xcode DEVICE BUILD fail in a
way that reads as a signing problem -- the phone pairs over the network, so
killing Wi-Fi kills the debugger connection, not the certificate. Recorded
because it has already cost time once.

## Open questions

- Whether the house is expected to be reachable at a stable name on the tailnet,
  or whether the client needs to discover it.
- Whether the local-only rule for pairing management extends to the tailnet, or
  whether those routes get a second gate.
- What the client shows when the house is simply not up. "Waiting to be told
  where the house is" is right for an unconfigured client and wrong for a
  configured one whose house is asleep at home.
