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
    'hero.subtitle': 'A keyboard-first spatial companion browser for macOS. Built for parallel web tasks, AI chats, research, development, and terminal workflows.',
    'install.title': 'Install via Homebrew Cask',
    'install.note': 'Auto-updates with `brew upgrade --cask den-browser`.',
    'copy': 'Copy',
    'copied': 'Copied!',
    'keyboard.hint': 'Press Control + , to enter Den Mode and orchestrate layouts.',
    'features.title': 'Orchestrate your web workflow',
    'features.subtitle': 'No more tab list clutter. Den Browser maps spatial window management directly to Desks, Boards, and Drawers.',
    'features.niri.title': 'Niri-Inspired Spatial Canvas',
    'features.niri.desc': 'Inspired by the Niri scrollable tiling window manager, web tasks sit side-by-side on an infinite horizontal strip. Boards never overlap or hide behind tabs—glide smoothly across your workspace.',
    'features.terminal.title': 'Integrated Terminal & Zellij',
    'features.terminal.desc': 'Place native shell, Zellij, or zmx terminal sessions side-by-side with your Web Boards on the same Desk. Seamlessly bridge web research and CLI tasks from your keyboard.',
    'features.ubol.title': 'Built-in Content Blocking (uBOL)',
    'features.ubol.desc': 'Bundled with uBlock Origin Lite out of the box. Blocks intrusive ads, popups, and trackers for a lightweight, distraction-free web experience.',
    'features.keyboard.title': 'Keyboard-First Control',
    'features.keyboard.desc': 'Toggle Den Mode (`Ctrl + ,`) or use Vim-style commands to navigate and resize boards (`-`/`=`), switch desks, and launch saved Essentials (`g`) purely from the keyboard.',
    'features.drawer.title': 'Shared Drawer & History',
    'features.drawer.desc': 'Capture links opened from external apps into a Den-wide Drawer (`a`) without disrupting your active Desk. Preview, filter, place (`p`), discard (`x`), or restore (`u`) anytime.',
    'features.focus.title': 'Zen View & Focus Mode',
    'features.focus.desc': 'Press `z` for Zen View to strip away all UI chrome, or `Shift + F` for Focus Mode to softly dim background boards and zero in on your active task.',
    'footer.rights': 'All rights reserved.',
    'legal.privacy': 'Privacy Policy',
    'legal.terms': 'Terms of Service',
  },
  ja: {
    'nav.features': '機能特徴',
    'nav.download': 'インストール',
    'nav.github': 'GitHub',
    'hero.subtitle': 'macOSのための、キーボードファーストな空間ブラウザ。調査、AIチャット、開発、執筆など、長時間続くWeb・ターミナル作業のために設計。',
    'install.title': 'Homebrew Cask でインストール',
    'install.note': '`brew upgrade --cask den-browser` でアップデート可能です。',
    'copy': 'コピー',
    'copied': 'コピー完了!',
    'keyboard.hint': 'Control + , を入力して Den Mode を切り替え、レイアウトを操作します。',
    'features.title': 'Webでの並行作業をオーケストレートする',
    'features.subtitle': 'もうタブ一覧に迷い込む必要はありません。Den Browserは空間的なウィンドウ管理のアイデアをDesk・Board・DrawerとしてWebに適用します。',
    'features.niri.title': 'Niriライクな空間キャンバス',
    'features.niri.desc': 'スクロール型ウィンドウマネージャー「Niri」にインスパイアされた無限横スクロール構造。Webページがタブのように重なって隠れることがなく、空間記憶を活かしてスムーズに移動できます。',
    'features.terminal.title': 'ターミナル & Zellij 統合',
    'features.terminal.desc': 'WebのBoardと同じDesk上に、通常のシェルやZellij/zmxセッションを並列配置。Web調査とCLI作業の行き来を、キーボード操作でシームレスに完結できます。',
    'features.ubol.title': 'uBlock Origin Lite 内蔵',
    'features.ubol.desc': 'uBlock Origin Lite（uBOL）を標準搭載。不要な広告やトラッカーを効果的に遮断し、軽快でクリーンなブラウジング環境を提供します。',
    'features.keyboard.title': 'キーボード主体の操作設計',
    'features.keyboard.desc': 'Den Mode (`Ctrl + ,`) やVim風操作で画面全体を制御。ボードの切り替えや伸縮 (`-`/`=`)、デスク移動、よく使う入力の呼び出し (Essentials: `g`) がキーボードから行えます。',
    'features.drawer.title': '一時保管庫 (Drawer) と復元',
    'features.drawer.desc': '外部アプリから開いたリンクや一時保存（`a`）したURLをDeskのレイアウトを崩さずにキープ。インラインプレビュー、フィルタ、Deskへの配置（`p`）、破棄（`x`）と復元（`u`）に対応。',
    'features.focus.title': 'Zen View と Focus Mode',
    'features.focus.desc': '`z` キーでUI表示を消し去る「Zen View」、`Shift + F` でフォーカス中のBoard以外をソフトに減光・ぼかす「Focus Mode」により、作業への深い没入をサポートします。',
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
