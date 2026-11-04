class_name FullRunNet
extends RefCounted
## One bounded, synchronous HTTP GET for the P2.22 full-run driver.
##
## The driver runs as a real scene, so autoloads and signals exist — but the
## preflight needs `/props` before the first turn, and an `HTTPRequest` node is
## async. This is the same blocking HTTPClient pattern `tools/scenario_playthrough.gd`
## uses: poll the client, read the body, give up cleanly. A dead server returns
## `{ok: false}` instead of hanging the driver, so a missing llama-server is a
## readable error, not a frozen run.


## GET `path` from `base_url` (e.g. "http://127.0.0.1:8089" + "/props").
## Returns {"ok": bool, "text": String}; never throws.
static func get_text(base_url: String, path: String) -> Dictionary:
	var rest := base_url
	var scheme := "http"
	if rest.contains("://"):
		var prefix := rest.split("://", false)
		scheme = prefix[0]
		rest = prefix[1]
	var slash := rest.find("/")
	var host_port := rest if slash < 0 else rest.substr(0, slash)
	var request_path := path if slash < 0 else rest.substr(slash) + path
	var host := host_port
	var port := 80
	if host_port.contains(":"):
		var bits := host_port.rsplit(":", true, 1)
		host = bits[0]
		port = int(bits[1])
	var tls: TLSOptions = TLSOptions.client() if scheme == "https" else null
	var client := HTTPClient.new()
	if client.connect_to_host(host, port, tls) != OK:
		return {"ok": false, "text": ""}
	var guard := 0
	while client.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
		client.poll()
		OS.delay_msec(10)
		guard += 1
		if guard > 300:
			break
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return {"ok": false, "text": ""}
	var headers: PackedStringArray = ["Content-Type: application/json"]
	if client.request(HTTPClient.METHOD_GET, request_path, headers, "") != OK:
		client.close()
		return {"ok": false, "text": ""}
	var body := PackedByteArray()
	while true:
		client.poll()
		var status := client.get_status()
		if status == HTTPClient.STATUS_BODY:
			var chunk := client.read_response_body_chunk()
			if chunk.size() > 0:
				body.append_array(chunk)
			else:
				OS.delay_msec(5)
		elif status == HTTPClient.STATUS_CONNECTED or status == HTTPClient.STATUS_DISCONNECTED:
			break
		elif (
			status
			in [
				HTTPClient.STATUS_CANT_CONNECT,
				HTTPClient.STATUS_CANT_RESOLVE,
				HTTPClient.STATUS_CONNECTION_ERROR,
				HTTPClient.STATUS_TLS_HANDSHAKE_ERROR,
			]
		):
			client.close()
			return {"ok": false, "text": ""}
		else:
			OS.delay_msec(5)
	var text := body.get_string_from_utf8()
	client.close()
	return {"ok": true, "text": text}
