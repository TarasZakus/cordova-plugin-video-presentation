"use strict";

function VideoPresentation() {
}

VideoPresentation.prototype.start = function (mediaUrl, wsOptions, successCallback, errorCallback) {
	cordova.exec(function (data) {
		successCallback(); // In case we successfully connected to WS-server.

		cordova.exec(null, null, "VideoPresentation", "start", [mediaUrl, data.webSocketId]); // Second, register listeners and start the presentation.
	}, errorCallback, "VideoPresentation", "wsConnect", [wsOptions]); // First, try to connect to the WS-server.
};

if (!window.plugins) {
	window.plugins = {};
}
window.plugins.videoPresentation = new VideoPresentation();
