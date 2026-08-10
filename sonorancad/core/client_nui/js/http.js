$(function () {
	window.addEventListener('message', function (event) {
		if (event.data.type == "light_event") {
			fetch("http://127.0.0.1:" + event.data.port + "/lighting", {
				method: "POST",
				headers: { "Content-Type": "application/json; charset=UTF-8" },
				body: JSON.stringify({ state: event.data.event })
			}).then(function (response) {
				if (!response.ok) console.warn("Sonoran Studio lighting rejected event " + event.data.event + " with status " + response.status)
			}).catch(function (error) {
				console.warn("Sonoran Studio lighting is unavailable: " + error.message)
			})
		} else if (event.data.type == "studio_game_event") {
			fetch("http://127.0.0.1:" + event.data.port + "/fivem", {
				method: "POST",
				headers: { "Content-Type": "application/json; charset=UTF-8" },
				body: JSON.stringify({ event: event.data.event, args: event.data.args || {} })
			}).then(function (response) {
				if (!response.ok) console.warn("Sonoran Studio rejected game event " + event.data.event + " with status " + response.status)
			}).catch(function (error) {
				console.warn("Sonoran Studio is unavailable: " + error.message)
			})
		}
    });
});
