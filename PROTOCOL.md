# DDRDesk protocol v1

Copy of the host protocol. Keep in sync with https://github.com/ddr-ai/ddrdesk-host/blob/main/PROTOCOL.md

Direct TLS 1.3 connection. No rendezvous, no relay, no third-party server.

## Transport

- TCP port **44789** (also advertised over mDNS as `_ddrdesk._tcp`).
- TLS 1.3, ALPN `ddrdesk/1`.
- Server uses a self-signed certificate generated on first run. The client pins the certificate fingerprint after the first successful authentication (TOFU).
- `TCP_NODELAY` is required.

## Framing

Every message:

```
u32be length     # number of bytes that follow (type + payload)
u8    type
u8[]  payload    # length-1 bytes
```

Maximum payload: 8 MiB.

## Message types

| Type | Name           | Payload                                      |
|------|----------------|----------------------------------------------|
| 0x01 | ClientHello    | UTF-8 JSON                                   |
| 0x02 | ServerHello    | UTF-8 JSON                                   |
| 0x03 | AuthFail       | UTF-8 JSON `{ "error": "..." }`              |
| 0x04 | Viewport       | UTF-8 JSON                                   |
| 0x05 | Input          | UTF-8 JSON                                   |
| 0x06 | Video          | `u8 flags` + `u64be pts_us` + Annex-B H.264  |
| 0x07 | Ping           | `u64be` client timestamp µs                  |
| 0x08 | Pong           | `u64be` client ts + `u64be` server ts        |
| 0x09 | RequestKeyframe| empty                                        |
| 0x0A | Status         | UTF-8 JSON `{ "state": "...", "msg": "..." }`|
| 0x0B | Goodbye        | optional UTF-8 reason                        |
| 0x0C | BitrateHint    | UTF-8 JSON `{ "kbps": 4000 }`                |

Video `flags` bit 0 = keyframe (includes SPS/PPS when set).

## ClientHello

```json
{
  "id": "582914337",
  "device": "iPhone",
  "w": 2556,
  "h": 1179,
  "points_w": 852,
  "points_h": 393,
  "scale": 3.0,
  "orientation": "landscape",
  "proto": 1,
  "session": null
}
```

## Input

```json
{"t":"move","dx":4.0,"dy":-2.5}
{"t":"btn","b":"left","d":true}
{"t":"btn","b":"right","d":false}
{"t":"wheel","dx":0,"dy":-1}
{"t":"key","k":"return","d":true}
{"t":"text","s":"password"}
```

Native iOS keyboard produces `text` and special `key` events. The touchscreen is a relative trackpad (`move` / `btn`).
