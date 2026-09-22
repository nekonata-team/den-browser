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
    'features.ubol.title': 'Optional Content Blocking (uBOL)',
    'features.ubol.desc': 'Optionally install uBlock Origin Lite to block intrusive ads, popups, and trackers for a lightweight, distraction-free web experience.',
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
    'features.keyboard.desc': 'Den Mode（`Ctrl + ,`）でボード伸縮やデスク移動。さらにWeb画面内もVim風キーバインド（スクロールやリンクヒント `f`）に対応。マウスに手を伸ばさず、Webとワークスペース全体を巡回できます。',
    'features.drawer.title': '一時保管庫（Drawer）と復元',
    'features.drawer.desc': '外部アプリから開いたリンクや一時保存（`a`）したURLをDeskのレイアウトを崩さずにキープ。インラインプレビュー、フィルタ、Deskへの配置（`p`）、破棄（`x`）と復元（`u`）に対応。',
    'features.ubol.title': 'uBlock Origin Lite対応（任意インストール）',
    'features.ubol.desc': 'uBlock Origin Lite（uBOL）を必要に応じてインストールして使用できます。不要な広告やトラッカーを効果的に遮断し、軽快でクリーンなブラウジング環境を提供します。',
    'footer.rights': 'All rights reserved.',
    'legal.privacy': 'プライバシーポリシー',
    'legal.terms': '利用規約',
  },
} as const;

type InlinePart = string | { code: string };

export const home = {
  en: {
    title: 'Web and terminal work, the Niri way',
    hero: {
      title: 'Web and terminal work, ',
      accent: 'the Niri way.',
      subtitle: 'A keyboard-first spatial companion browser for macOS. Built for parallel web tasks, research, development, and humans working side-by-side with AI coding agents.',
      cta: 'Install Den Browser',
    },
    video: {
      label: 'Den Browser Showcase',
      fallback: 'Your browser does not support the video tag.',
      play: 'Play video',
    },
    install: {
      title: 'Install via Homebrew Cask',
      copyCommand: 'Copy install command',
      skillAudience: 'Claude Code, Codex, etc.',
      copySkillCommand: 'Copy agent skill command',
      note: [
        'Homebrew updates with ',
        { code: 'brew upgrade --cask den-browser' },
        '. Terminal Boards drive adjacent Web Boards via bundled ',
        { code: 'den' },
        ' CLI.',
      ] satisfies InlinePart[],
      release: 'Download from GitHub Releases',
    },
    concept: {
      eyebrow: 'Concept',
      title: 'No Tabs. Just persistent physical space.',
      description: 'Den Browser replaces ephemeral browser tabs with structured, persistent surfaces designed for long-running work.',
      items: [
        {
          eyebrow: 'Broad Context',
          tone: 'cyan',
          title: 'Desk',
          label: '',
          description: 'A horizontal work area representing a broad task context. Switch between multiple desks instantly from the keyboard without losing your place.',
        },
        {
          eyebrow: 'Surface',
          tone: 'purple',
          title: 'Board',
          label: '',
          description: 'A focused column representing a single task. Holds either a Web Sheet stack or a live native Terminal session side-by-side.',
        },
        {
          eyebrow: 'Content',
          tone: 'pink',
          title: 'Sheet & Terminal',
          label: '',
          description: 'Web screens held within a board with persistent navigation history, or interactive Terminal, Zellij, and AI coding agent sessions.',
        },
      ],
    },
    features: {
      title: 'Orchestrate your web workflow',
      subtitle: 'No more tab list clutter. Den Browser maps spatial window management directly to Desks, Boards, and Drawers.',
      items: [
        {
          icon: 'canvas',
          title: 'Niri-Inspired Spatial Canvas',
          description: ['Inspired by the Niri scrollable tiling window manager, web tasks sit side-by-side on an infinite horizontal strip. Boards never overlap or hide behind tabs—glide smoothly across your workspace.'] satisfies InlinePart[],
        },
        {
          icon: 'terminal',
          title: 'Integrated Terminal',
          description: ['Place native shell, Zellij, or zmx terminal sessions side-by-side with your Web Boards on the same Desk. Seamlessly bridge web research and CLI tasks from your keyboard.'] satisfies InlinePart[],
        },
        {
          icon: 'agent',
          title: 'Built for Humans & AI Agents',
          description: [
            'The bundled ',
            { code: 'den' },
            ' CLI lets coding agents (Claude Code, Codex, etc.) inspect and drive Web Boards right from an adjacent Terminal Board. Uses token-efficient DOM snapshots (',
            { code: '@e1' },
            ', ',
            { code: '@e2' },
            ') with zero setup.',
          ] satisfies InlinePart[],
        },
        {
          icon: 'keyboard',
          title: 'Keyboard-First & Vim Navigation',
          description: [
            'Toggle Den Mode (',
            { code: 'Ctrl + ,' },
            ') to manage boards and desks, and navigate web sheets mouse-free with first-party Vim keybindings (scrolling, link hints with ',
            { code: 'f' },
            '). Complete control without touching the mouse.',
          ] satisfies InlinePart[],
        },
        {
          icon: 'drawer',
          title: 'Shared Drawer & History',
          description: [
            'Capture links opened from external apps into a Den-wide Drawer (',
            { code: 'a' },
            ') without disrupting your active Desk. Preview, filter, place (',
            { code: 'p' },
            '), discard (',
            { code: 'x' },
            '), or restore (',
            { code: 'u' },
            ') anytime.',
          ] satisfies InlinePart[],
        },
        {
          icon: 'ubol',
          title: 'Optional Content Blocking (uBOL)',
          description: ['Optionally install uBlock Origin Lite to block intrusive ads, popups, and trackers for a lightweight, distraction-free web experience.'] satisfies InlinePart[],
        },
      ],
    },
    cta: {
      title: 'Browse, build, and run side-by-side with AI agents.',
      description: 'Experience persistent spatial browsing, integrated terminals, and keyboard-first orchestration on macOS.',
    },
    script: {
      copyError: 'Failed to copy text: ',
      playbackError: 'Playback error/prevented: ',
    },
  },
  ja: {
    title: 'Webとターミナル作業を、Niriのように',
    hero: {
      title: 'Webとターミナル作業を、',
      accent: 'Niriのように。',
      subtitle: '長時間続くWeb・ターミナル作業のための、macOS向けキーボードファーストな空間ブラウザ。タブの山に迷うことなく、調査、開発、そして同じDeskで人間とAIエージェントが並走する作業空間を提供します。',
      cta: 'Den Browser をインストール',
    },
    video: {
      label: 'Den Browser デモ映像',
      fallback: 'お使いのブラウザはビデオ表示に対応していません。',
      play: '動画を再生',
    },
    install: {
      title: 'Homebrew Cask でインストール',
      copyCommand: 'インストールコマンドをコピー',
      skillAudience: 'Claude Code、Codex 等',
      copySkillCommand: 'Agent Skill インストールコマンドをコピー',
      note: [
        'Homebrew版は ',
        { code: 'brew upgrade --cask den-browser' },
        ' で更新。Terminal Boardから同梱の ',
        { code: 'den' },
        ' CLIで隣のWeb画面を操作できます。',
      ] satisfies InlinePart[],
      release: 'GitHub Releasesからダウンロード',
    },
    concept: {
      eyebrow: 'Concept',
      title: 'タブのないブラウジング。永続する作業空間へ。',
      description: 'Den Browser は散らかりがちな「ブラウザタブ」を廃止し、長期的な作業に最適化された永続する作業面（Desk・Board・Sheet/Terminal）を採用しています。',
      items: [
        {
          eyebrow: 'Broad Context',
          tone: 'cyan',
          title: 'Desk',
          label: ' / デスク',
          description: '作業文脈ごとに切り分けられた水平な作業領域。キーボードから複数のDeskを一瞬で行き来できます。',
        },
        {
          eyebrow: 'Surface',
          tone: 'purple',
          title: 'Board',
          label: ' / ボード',
          description: '1つのタスクを表す独立した作業面。Web SheetやライブなターミナルをDesk上に並べ、幅を自由に伸縮できます。',
        },
        {
          eyebrow: 'Content',
          tone: 'pink',
          title: 'Sheet & Terminal',
          label: '',
          description: 'Board内に保持される履歴スタック付きのWeb画面、または対話的なTerminal、Zellij、AIコーディングエージェントのセッション。',
        },
      ],
    },
    features: {
      title: 'Webでの並行作業をオーケストレートする',
      subtitle: 'もうタブの整理に追われる必要はありません。空間管理をDesk・Board・Drawerで直感的かつシンプルに設計しました。',
      items: [
        {
          icon: 'canvas',
          title: 'Niriライクな空間キャンバス',
          description: ['スクロール型ウィンドウマネージャー「Niri」にインスパイアされた無限横スクロール構造。Webページがタブのように重なって隠れることがなく、空間記憶を活かしてスムーズに移動できます。'] satisfies InlinePart[],
        },
        {
          icon: 'terminal',
          title: '統合ターミナル',
          description: ['WebのBoardと同じDesk上に、通常のシェルやZellij/zmxセッションを並列配置。Web調査とCLI作業の行き来を、キーボード操作でシームレスに完結できます。'] satisfies InlinePart[],
        },
        {
          icon: 'agent',
          title: '人間とAIエージェントの並走',
          description: [
            '同梱の ',
            { code: 'den' },
            ' CLI により、Terminal Board で動く AI コーディングエージェント（Claude Code、Codex 等）が隣接する Web Board を直接操作。CDP 不要・設定ゼロで、トークン消費を抑えた軽量 Snapshot（',
            { code: '@e1' },
            ', ',
            { code: '@e2' },
            '）を使って画面を検証できます。',
          ] satisfies InlinePart[],
        },
        {
          icon: 'keyboard',
          title: 'キーボード & Vim ナビゲーション',
          description: [
            'Den Mode（',
            { code: 'Ctrl + ,' },
            '）でボード伸縮やデスク移動。さらにWeb画面内もVim風キーバインド（スクロールやリンクヒント ',
            { code: 'f' },
            '）に対応。マウスに手を伸ばさず、Webとワークスペース全体を巡回できます。',
          ] satisfies InlinePart[],
        },
        {
          icon: 'drawer',
          title: '一時保管庫（Drawer）と復元',
          description: [
            '外部アプリから開いたリンクや一時保存（',
            { code: 'a' },
            '）したURLをDeskのレイアウトを崩さずにキープ。インラインプレビュー、フィルタ、Deskへの配置（',
            { code: 'p' },
            '）、破棄（',
            { code: 'x' },
            '）と復元（',
            { code: 'u' },
            '）に対応。',
          ] satisfies InlinePart[],
        },
        {
          icon: 'ubol',
          title: 'uBlock Origin Lite対応（任意インストール）',
          description: ['uBlock Origin Lite（uBOL）を必要に応じてインストールして使用できます。不要な広告やトラッカーを効果的に遮断し、軽快でクリーンなブラウジング環境を提供します。'] satisfies InlinePart[],
        },
      ],
    },
    cta: {
      title: 'Webも、開発も、AIエージェントとの並走も。',
      description: '永続する空間キャンバス、統合ターミナル、そして完全なキーボード操作を体験してください。',
    },
    script: {
      copyError: 'コピーできませんでした: ',
      playbackError: '再生できませんでした: ',
    },
  },
} as const;

export type HomeCopy = (typeof home)['en'];

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
