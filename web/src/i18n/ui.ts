export const languages = {
  en: 'English',
  ja: '日本語',
};

export const defaultLang = 'en';

export const ui = {
  en: {
    'nav.features': 'Features',
    'nav.download': 'Download',
    'nav.github': 'GitHub',
    'hero.subtitle': 'A keyboard-first spatial companion browser for macOS. Built for parallel web tasks, research, development, and humans working side-by-side with AI coding agents.',
    'install.title': 'Install via Homebrew Cask',
    'install.agent': 'Install Agent Skill',
    'install.note': 'Auto-updates with `brew upgrade --cask den-browser`.',
    'copy': 'Copy',
    'copied': 'Copied!',
    'keyboard.hint': 'Press Control + , to enter Den Mode and orchestrate layouts.',
    'features.title': 'Orchestrate your web workflow',
    'features.subtitle': 'No more tab list clutter. Den Browser maps spatial window management directly to Desks, Boards, and Drawers.',
    'features.niri.title': 'Niri-Inspired Spatial Canvas',
    'features.niri.desc': 'Inspired by the Niri scrollable tiling window manager, web tasks sit side-by-side on an infinite horizontal strip. Boards never overlap or hide behind tabs—glide smoothly across your workspace.',
    'features.terminal.title': 'Integrated Terminal',
    'features.terminal.desc': 'Place native shell, Zellij, or zmx terminal sessions side-by-side with your Web Boards on the same Desk. Seamlessly bridge web research and CLI tasks from your keyboard.',
    'features.agent.title': 'Built for Humans & AI Agents',
    'features.agent.desc': 'The bundled `den` CLI lets coding agents (Claude Code, Codex, etc.) inspect and drive Web Boards right from an adjacent Terminal Board. Uses token-efficient DOM snapshots (`@e1`, `@e2`) with zero setup.',
    'features.keyboard.title': 'Keyboard-First & Vim Navigation',
    'features.keyboard.desc': 'Toggle Den Mode (`Ctrl + ,`) to manage boards and desks, and navigate web sheets mouse-free with first-party Vim keybindings (scrolling, link hints with `f`). Complete control without touching the mouse.',
    'features.drawer.title': 'Shared Drawer & History',
    'features.drawer.desc': 'Capture links opened from external apps into a Den-wide Drawer (`a`) without disrupting your active Desk. Preview, filter, place (`p`), discard (`x`), or restore (`u`) anytime.',
    'features.ubol.title': 'Built-in Content Blocking (uBOL)',
    'features.ubol.desc': 'Bundled with uBlock Origin Lite out of the box. Blocks intrusive ads, popups, and trackers for a lightweight, distraction-free web experience.',
    'footer.rights': 'All rights reserved.',
    'legal.privacy': 'Privacy Policy',
    'legal.terms': 'Terms of Service',
  },
  ja: {
    'nav.features': '機能特徴',
    'nav.download': 'インストール',
    'nav.github': 'GitHub',
    'hero.subtitle': 'macOSのための、キーボードファーストな空間ブラウザ。調査や開発、そして同じDeskで人間とAIエージェントが並走する作業空間のために設計。',
    'install.title': 'Homebrew Cask でインストール',
    'install.agent': 'Agent Skill をインストール',
    'install.note': '`brew upgrade --cask den-browser` でアップデート可能です。',
    'copy': 'コピー',
    'copied': 'コピー完了!',
    'keyboard.hint': 'Control + , を入力して Den Mode を切り替え、レイアウトを操作します。',
    'features.title': 'Webでの並行作業をオーケストレートする',
    'features.subtitle': 'もうタブ一覧に迷い込む必要はありません。Den Browserは空間的なウィンドウ管理のアイデアをDesk・Board・DrawerとしてWebに適用します。',
    'features.niri.title': 'Niriライクな空間キャンバス',
    'features.niri.desc': 'スクロール型ウィンドウマネージャー「Niri」にインスパイアされた無限横スクロール構造。Webページがタブのように重なって隠れることがなく、空間記憶を活かしてスムーズに移動できます。',
    'features.terminal.title': '統合ターミナル',
    'features.terminal.desc': 'WebのBoardと同じDesk上に、通常のシェルやZellij/zmxセッションを並列配置。Web調査とCLI作業の行き来を、キーボード操作でシームレスに完結できます。',
    'features.agent.title': '人間とAIエージェントの並走',
    'features.agent.desc': '同梱の `den` CLI により、Terminal Board で動く AI コーディングエージェント（Claude Code、Codex 等）が隣接する Web Board を直接操作。CDP 不要・設定ゼロで、トークン消費を抑えた軽量 Snapshot（`@e1`, `@e2`）を使って画面を検証できます。',
    'features.keyboard.title': 'キーボード & Vim ナビゲーション',
    'features.keyboard.desc': 'Den Mode (`Ctrl + ,`) でボード伸縮やデスク移動。さらにWeb画面内もVim風キーバインド（スクロールやリンクヒント `f`）に対応。マウスに手を伸ばさず、Webとワークスペース全体を巡回できます。',
    'features.drawer.title': '一時保管庫 (Drawer) と復元',
    'features.drawer.desc': '外部アプリから開いたリンクや一時保存（`a`）したURLをDeskのレイアウトを崩さずにキープ。インラインプレビュー、フィルタ、Deskへの配置（`p`）、破棄（`x`）と復元（`u`）に対応。',
    'features.ubol.title': 'uBlock Origin Lite 内蔵',
    'features.ubol.desc': 'uBlock Origin Lite（uBOL）を標準搭載。不要な広告やトラッカーを効果的に遮断し、軽快でクリーンなブラウジング環境を提供します。',
    'footer.rights': 'All rights reserved.',
    'legal.privacy': 'プライバシーポリシー',
    'legal.terms': '利用規約',
  },
} as const;

export function getLangFromUrl(url: URL) {
  const [, lang] = url.pathname.split('/');
  if (lang in ui) return lang as keyof typeof ui;
  return defaultLang;
}

export function useTranslations(lang: keyof typeof ui) {
  return function t(key: keyof typeof ui[typeof lang]) {
    return ui[lang][key] || ui[defaultLang][key];
  };
}
