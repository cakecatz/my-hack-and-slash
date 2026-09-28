# EMBER / 深淵の狩人 — ロードマップと残課題

最終更新: 2026-09-28

新しいセッションでは**まずこの文書を読む**。完了・未完了・優先度・設計上の約束・テスト方法をここに集約する。
個別仕様は [README.md](../README.md) と [GAME_DESIGN.md](GAME_DESIGN.md)、旧時点の評価は [ASSESSMENT.md](ASSESSMENT.md)・[NEXT_IDEAS.md](NEXT_IDEAS.md) を参照（いずれも 2026-09-22 時点で一部陳腐化）。

---

## 0. 現状サマリ

- 状態: **本編（3章9遠征）〜深淵（深度1〜5）が通しで動く初期アルファ**。自動テストは14本すべて緑。
- 直近セッションで「見た目・導入・ビルド基盤」を大きく前進させた。
- まだ製品品質ではない最大要因: **専用アート・アニメ、BGM/環境音、人間による通しプレイの難度・時間調整**。

---

## 1. 完了（実装済み）

### シェル / UI・導入
- タイトル画面（New Game / Continue / Settings / Quit、セーブサマリ、上書き確認）
- ポーズメニュー（再開 / 設定 / 操作一覧 / タイトルへ / 終了）
- 日本語フォント（`assets/fonts/NotoSansJP-Regular/Bold.otf` + `OFL.txt`、`assets/theme/ember_theme.tres`）
- 画面表記の日本語化（`scripts/loc.gd`、`label_at` 経由で適用）
- 導入・ヒント用の UI状態（`scripts/ui_state.gd` → `user://ui_state.cfg`）
- HUD整理（体力 / 熱量 / マナ / 目標トラッカー / スキルバー / ミニマップ / ボスバー、メッセージは一時表示）

### ビルド
- **スキルプール8種**（攻撃: CLEAVE / NOVA / LANCE / EMBER BOLT、アクティブ: EMBER LANCE / CINDER FIELD / GUARDIAN BARRIER / BLOOD RUSH）を、**基本枠（クリック）+ アクティブ枠1〜4**へ自由に割り当て
- **タグ制サポート10種**、**スロット別リンク**（各最大5）、**同一サポートは1キャラ1つ**、**Tier（T3→T1）**で強化（右クリック、残火消費）
- **アクティブスキルにもレベル**（8スキルすべて Lv.1〜10、装備中が撃破XPで同時に成長）
- **マナ**（アクティブ枠のコスト、自然回復、足りないと発動不可）
- **霊力 + オーラ4種**（予約制の常時バフ: ASH / WARD / EMBER FLOW / FLEET）
- 才能4種（剛力 / 体力 / 速さ / 精神）
- パッシブツリー（19ノード / 12点 / 3系統 / タグ連動ノード、`scripts/passive_tree.gd`）
- ビルド保存3枠（スキル・リンク・才能・アクティブ枠・オーラ）

### 装備 / 戦闘
- 装備3部位・4レアリティ・接頭接尾Mod（T3〜T1）・Mod指定クラフト・鍛冶+3・ルーン
- Relic 3種（スキル挙動を変える固有装備）
- 投射物システム、精鋭3特性、ボス3種の予兆攻撃と反撃の隙
- 代償付き祭壇、呪われた宝箱（任意の4体戦）

### 世界 / 周回
- 遠征マップ: **手作りテンプレート3種 × 鏡像反転**をランダム選択（`scripts/expedition_layout.gd`）
- **試し斬り場**（DPS計測、練習場内でビルド・装備変更可）
- 拠点 ⇄ 遠征の短い周回、自動回収/分解保護/ソート

### 保存
- `user://character.json` **v8**（v1〜v7 から移行）

---

## 2. PoE / TLI 比較の残課題（優先度順）

「優先度A-1〜A-3、B-7」は実装済み。以下は未着手または一部。

### 優先度A: ビルドの骨格
| ID | 項目 | 内容 | 規模 | 状態 |
| --- | --- | --- | --- | --- |
| A-1 | サポートのスキル別化 | 各スロットが独立リンク・同一不可 | 中 | **完了** |
| A-2 | アクティブのレベル | 8スキル Lv.1〜10 | 中 | **完了** |
| A-3 | サポートTier | T3→T1、右クリック強化 | 小〜中 | **完了** |
| A-4 | **ダメージ種別・耐性・貫通** | 物理/火/冷/雷/混沌、耐性、貫通、変換 | 大 | 未着手 |
| A-5 | 会心・命中/回避 | クリ率/クリダメ、命中/回避値 | 中〜大 | 未着手 |
| A-6 | 状態異常の型 | 発火/冷却/凍結/感電/毒、閾値・免疫 | 中 | 一部（燃焼・減速・露出のみ） |

### 優先度B: リソースと常時効果
| ID | 項目 | 内容 | 規模 | 状態 |
| --- | --- | --- | --- | --- |
| B-7 | 予約リソース＋オーラ | 霊力＋常時バフ | 中 | **完了** |
| B-8 | **フラスコ／チャーム** | チャージ制の回復・一時バフ | 中 | 未着手 |
| B-9 | 第2の防御軸 | エネルギーシールド／ブロック | 中 | 未着手 |

### 優先度C: アイテムとクラフト
| ID | 項目 | 内容 | 規模 | 状態 |
| --- | --- | --- | --- | --- |
| C-10 | 装備部位を増やす | 手袋/靴/指輪の1〜2 | 中 | 未着手 |
| C-11 | アイテムLvとベース | ilvlで接辞Tierを解放 | 中 | 未着手 |
| C-12 | 装備ソケット | ルーン/ジェム枠 | 中 | 未着手 |
| C-13 | ランダム再抽選クラフト | 混沌相当＋第2通貨 | 中 | 未着手 |
| C-14 | レジェンダリー拡充 | ビルドを定義する固有効果 | 中 | 一部（Relic 3種） |

### 優先度D: パッシブとキャラ個性
| ID | 項目 | 内容 | 規模 | 状態 |
| --- | --- | --- | --- | --- |
| D-15 | キーストーン | 有利＋不利でルールを変えるノード | 小 | 未着手 |
| D-16 | 宝石/ルーン枠をツリーに | ソケットノード | 小〜中 | 未着手 |
| D-17 | 開始アーキタイプ＋昇華相当 | 章クリア時の二択など | 中 | 未着手 |

### 優先度E: エンドゲームとメタ
| ID | 項目 | 内容 | 規模 | 状態 |
| --- | --- | --- | --- | --- |
| E-18 | 深淵のマップ修飾子 | 深度＋任意修飾子で報酬増 | 中 | 一部（危険条件3種） |
| E-19 | ピナクルボス | 深淵最上位の専用ボス | 中 | 未着手 |
| E-20 | ビルド共有テキスト | プリセットの書き出し/読み込み | 小 | 未着手 |
| E-21 | ルートフィルタ | レアリティ/部位で表示・自動分解 | 小〜中 | 未着手 |
| E-22 | ストッシュのタブ化・複数キャラ枠 | 整理とキャラ枠 | 小〜中 | 未着手 |

### 優先度F: 仲間・演出・その他
| ID | 項目 | 内容 | 規模 | 状態 |
| --- | --- | --- | --- | --- |
| F-23 | 仲間（Pactspirit相当） | 常時効果の仲間 | 中 | 未着手（オーラは完了） |
| F-24 | BGM・環境音 | 拠点/章/ボス/深淵、動的切替 | 中〜大 | 未着手 |
| — | コントローラー＋リバインド | パッド・UIフォーカス | 中 | 未着手 |
| — | フォントのサブセット化 | 未使用グリフ削減 | 小 | 未着手（現在フル同梱） |
| — | 人間の通しプレイ計測 | 30〜60分・難度・死亡箇所 | — | 未実施（重要） |

---

## 3. 意図的に真似しないもの（この規模では逆効果）

- 1325ノード級のパッシブツリー、7クラス×多数昇華
- ジェムの色・ソケット連結（PoE1の色合わせ）
- トレード、シーズン制、MTX、大量の接尾辞プール
- アイテムの無限階層インフレ（深淵は深度5で区切る方針を維持）

---

## 4. 設計上の約束（新セッション向け・重要）

- **テスト互換**: 全テストは `scenes/main.tscn` を `save_enabled = false` で生成し、`hub` 開始を前提にする。タイトル／導入は `save_enabled == true` のときだけ有効化する。
- **固定座標のテスト**: `tests/journey.gd` / `build_identity.gd` / `bosses.gd` / `shrine.gd` は決定的なレイアウトを前提にしている。冒頭で `scene.layout_template = 0` / `scene.layout_flip = 0` を設定する。
- **保存形式 v8**: 項目を足すときは `load_from` の検証・移行とテストを同時に更新する。旧セーブの移行を壊さない。
- **描画**: 即時描画（`_draw`）。文字は `label_at` 経由で `scripts/loc.gd` を引く。書式付き文字列は `Loc.t("...") % [...]` とラップする。
- **言語**: UIは日本語。固有名詞（EMBER / CLEAVE / POWER など）は英語のまま。
- **乱数**: テストで固定できるよう、乱択する機能は明示的な変数を用意する（例: `layout_template` / `layout_flip`）。
- **テストは実キャラを触らない**: 一時セーブのみ使用する。

---

## 5. テスト

```sh
godot --headless --log-file /tmp/ember-smoke.log    --path . --script tests/smoke.gd
godot --headless --log-file /tmp/ember-shell.log    --path . --script tests/shell.gd
godot --headless --log-file /tmp/ember-journey.log  --path . --script tests/journey.gd
godot --headless --log-file /tmp/ember-mastery.log  --path . --script tests/mastery.gd
godot --headless --log-file /tmp/ember-qol.log      --path . --script tests/expedition_qol.gd
godot --headless --log-file /tmp/ember-identity.log --path . --script tests/build_identity.gd
godot --headless --log-file /tmp/ember-bosses.log   --path . --script tests/bosses.gd
godot --headless --log-file /tmp/ember-feedback.log --path . --script tests/feedback.gd
godot --headless --log-file /tmp/ember-layout.log   --path . --script tests/layout.gd
godot --headless --log-file /tmp/ember-shrine.log   --path . --script tests/shrine.gd
godot --headless --log-file /tmp/ember-craft.log    --path . --script tests/crafting.gd
godot --headless --log-file /tmp/ember-training.log --path . --script tests/training.gd
godot --headless --log-file /tmp/ember-passives.log --path . --script tests/passives.gd
godot --headless --log-file /tmp/ember-abilities.log --path . --script tests/abilities.gd
```

- 進行テストは敵にテスト用ダメージを与えて倒すため、**難度・所要時間の検証には使えない**。
- 変更後は14本すべてを実行して緑を確認する。

---

## 6. 直近の次の一手（推奨）

1. **B-8 フラスコ／チャーム** — 現在のQポーション（固定3個・撃破で回復）をチャージ制に発展。アイコンと残量UIを伴う。
2. **A-4 ダメージ種別・耐性・貫通** — 種別 → 耐性 → 貫通 の順に段階導入。戦闘計算の基盤変更なので規模は大きい。
3. **人間の通しプレイ計測** — 30〜60分・死亡箇所・装備更新回数・構えの偏り。ここで難度と時間を調整する。
4. F-24 BGM・環境音、コントローラー対応、フォントのサブセット化（仕上げ工程）。

過去のPlanメモ（Tier 0/3のみ）は `~/.opencode/plan/ember-game-feel-plan.md` にあり、本ロードマップで置き換える。

---

## 7. 関連ドキュメント

- [README.md](../README.md) — 操作・各システムの詳細と開発メモ
- [GAME_DESIGN.md](GAME_DESIGN.md) — 企画・体験の軸・完成判定
- [ASSESSMENT.md](ASSESSMENT.md) — 2026-09-22 時点の評価（一部陳腐化）
- [NEXT_IDEAS.md](NEXT_IDEAS.md) — 2026-09-22 時点のアイデア（一部実装済み）
