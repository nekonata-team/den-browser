# Den `read` case register

Manually check [`den board web read`](../cli.md) against these live pages.

| Page | `--within` | Must retain | Must omit |
| --- | --- | --- | --- |
| [GitHub: cmark-gfm](https://github.com/github/cmark-gfm) | `article.markdown-body` | Installing heading, build commands on separate lines, spec link | Copy-code controls, repository file list |
| [Wikipedia: 東京タワー](https://ja.wikipedia.org/wiki/東京タワー) | `table.infobox` | `高さ` paired with `333 m`, `所在地` paired with the address | Raw `<table>` markup and its attributes |
| [MDN: data URLs](https://developer.mozilla.org/en-US/docs/Web/URI/Reference/Schemes/data) | `#content` | Visible `data:text/plain;base64,SGVsbG8sIFdvcmxkIQ==` example | A duplicate copy of the payload as the Markdown link destination |
