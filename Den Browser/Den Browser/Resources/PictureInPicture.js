(async () => {
    const mode = "__DEN_PICTURE_IN_PICTURE_MODE__";
    const videos = Array.from(document.querySelectorAll("video"));
    const activeVideo = videos.find(video =>
        !video.paused &&
        !video.ended &&
        video.readyState >= 2
    );

    const video =
        mode === "enter"
            ? activeVideo
            : (activeVideo ??
                videos.sort((a, b) =>
                    (b.clientWidth * b.clientHeight) -
                    (a.clientWidth * a.clientHeight)
                )[0]);

    if (!video) {
        if (mode === "enter") {
            return "no-playing-video";
        }
        throw new Error("NO_VIDEO");
    }

    if (document.pictureInPictureElement) {
        if (mode === "enter") {
            return "already-entered";
        }
        await document.exitPictureInPicture();
        return "exited";
    }

    if (
        document.pictureInPictureEnabled &&
        typeof video.requestPictureInPicture === "function"
    ) {
        await video.requestPictureInPicture();
        return "entered-standard";
    }

    if (
        typeof video.webkitSupportsPresentationMode === "function" &&
        video.webkitSupportsPresentationMode("picture-in-picture") &&
        typeof video.webkitSetPresentationMode === "function"
    ) {
        video.webkitSetPresentationMode("picture-in-picture");
        return "entered-webkit";
    }

    throw new Error("PIP_UNSUPPORTED");
})();
