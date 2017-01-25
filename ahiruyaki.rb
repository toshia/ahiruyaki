# -*- coding: utf-8 -*-

module Plugin::Ahiruyaki
  extend self
  STAMINA_RECOVER_SEC = 300     # 回復速度。無意味にパズドラとあわせる
  AHIRU_ID = 606860144
  RANK_TABLE = Enumerator.new do |yielder|
    a = 2
    b = 1
    loop do
      c = a + b/2
      yielder << c
      a, b = c, a end end
  PATTERN = Regexp.union(%w<あひる焼き Ahiruyaki 扒家鸭>)
end

Plugin.create(:ahiruyaki) do

  UserConfig[:ahiruyaki_stamina_recover_time] ||= Time.new
  UserConfig[:ahiruyaki_exp] ||= 0
  UserConfig[:ahiruyaki_stone] ||= 0
  strong_fire = Set.new()

  defactivity "ahiruyaki", 'あひる焼き'
  defactivity "ahiruyaki_info", 'あひる焼き（情報）'

  Delayer.new do
    rank_label.text = rank.to_s
    stamina_value_label.text = '%i'.freeze % stamina
    stamina_max_label.text = stamina_max.to_s
    stamina_progressbar.fraction = stamina.to_f / stamina_max
    exp_progressbar.fraction = (UserConfig[:ahiruyaki_exp] - exp()).to_f / (exp(rank+1) - exp())
    stone_label.text = stone.to_s
    rewind_stamina
    unless at(:is_stone_gave)
      store(:is_stone_gave, true)
      add_stone(rank, nil) end end

  # ユニットを定義する。ユニットを購入可能にする。
  # ==== Args
  # [name] Symbol 識別名
  # [price] Fixnum 価格。一段階アップグレードするのにこれだけの魔法石が必要になる
  # [icon] String アイコン画像のパス
  # [title] String 表示名。UI上にはこの名前で表示される
  defdsl :defahiruyaki do |name, price: 1, icon: fail, title: name.to_s|
    e_increase = :"ahiruyaki_#{name}"
    m_label = :"#{name}_label"
    m_modify_label = :"#{name}_label="
    m_button = :"#{name}_button"
    k_value = name.to_sym

    Delayer.new do
      self.__send__(m_modify_label, at(k_value, 0).to_s)
      self.__send__(m_button).sensitive = (stone >= price) end

    # あひる焼き強化ボタンの更新
    on_ahiruyaki_stone_changed do |stone|
      self.__send__(m_button).sensitive = (stone >= price) end

    # ボタンがクリックされるなど、魔法石を消費して強化する
    add_event(e_increase) do
      expend_stone(1) do
        store(k_value, 1 + at(k_value, 0))
        self.__send__(m_modify_label, at(k_value, 0).to_s) end end

    filter_ahiruyaki_unit do |container|
      container << self.__send__(m_button)
      [container] end

    eval(<<EOE)
    # 強化ボタンを返す
    # ==== Return
    # Gtk::Button
    def #{m_button.to_s}
      @#{m_button.to_s} ||= Gtk::Button.new()
                                  .add(Gtk::HBox.new()
                                        .closeup(Gtk::Image.new(Gdk::Pixbuf.new('#{icon}', 64, 64)))
                                        .add(Gtk::VBox.new
                                              .closeup(Gtk::Label.new('#{title}').left)
                                              .closeup(Gtk::Label.new('魔法石 x #{price.to_s}').left))
                                        .closeup(#{m_label.to_s}.right)) end

    # 強さを表示するラベル
    # ==== Return
    # Gtk::Label
    def #{m_label.to_s}
      @#{m_label.to_s} ||= Gtk::Label.new().set_use_markup(true) end

    # 表示されている強さを更新する
    # ==== Args
    # [power] 強さ
    def #{m_modify_label}(power)
      #{m_label.to_s}.set_markup(%q<<span size="%{size}">%{value}</span>> % {value: power.to_s, size: #{53 * 1024}})
      power end
EOE

    self.__send__(m_button).ssc(:clicked) do
      Plugin.call(e_increase)
      false end
  end

  defahiruyaki(:ahiruyaki_power,
               title: "あひる焼き強化",
               icon: File.join(__dir__, 'ahiru.png'))

  defahiruyaki(:ahiruyaki_welldone,
               price: 5,
               title: "めっちゃ強火",
               icon: File.join(__dir__, 'welldone.png'))

  defahiruyaki(:friendly_fire,
               price: 1,
               title: "フレンドリーファイア",
               icon: Skin.get('unfav.png'))

  on_appear do |messages|
    messages.lazy.reject(&:from_me?).select{ |message|
      message[:created] > defined_time
    }.select{ |message|
      Plugin::Ahiruyaki::PATTERN.match(message.to_s)
    }.each do |baking_message|
      expend_stamina(1) do
        baking_message.favorite
        add_experience [1, 1+at(:friendly_fire, 0)].max, "#{baking_message.user[:name]} さんがあひるを焼いた。" end end
  end

  on_mention do |service, messages|
    messages.lazy.select(&:has_receive_message?).select{ |message|
      message[:created] > defined_time
    }.select{ |message|
      Plugin::Ahiruyaki::AHIRU_ID == message.user.id
    }.select { |message|
      message.replyto_source.from_me? unless message.replyto_source.nil?
    }.select { |message|
      Plugin::Ahiruyaki::PATTERN.match(message.replyto_source.to_s)
    }.each do |message|
      if strong_fire.include? message.replyto_source.id
        add_experience [1, at(:ahiruyaki_welldone, 0), rank ** (1.5 + at(:ahiruyaki_welldone, 0)*0.0625)].max, "あひるを焼くなと言われた。\n強火ボーナス！"
        strong_fire.delete(message.id)
      else
        add_experience [1, at(:ahiruyaki_power, 0), rank ** (1 + at(:ahiruyaki_power, 0)*0.015625)].max, "あひるを焼くなと言われた。" end end
  end

  on_ahiruyaki_rankup do |after_rank|
    if after_rank == rank
      UserConfig[:ahiruyaki_stamina_recover_time] = Time.new
      Plugin.call :ahiruyaki_stamina_changed, stamina
      add_stone(1, "ランクアップボーナス！")
      rank_label.text = after_rank.to_s
      stamina_max_label.text = stamina_max.to_s
      exp_progressbar.fraction = (UserConfig[:ahiruyaki_exp] - exp()).to_f / (exp(rank+1) - exp())
    end
  end

  on_ahiruyaki_stamina_changed do |_stamina|
    stamina_value_label.text = '%i'.freeze % stamina
    stamina_progressbar.fraction = stamina.to_f / stamina_max
    if _stamina >= stamina_max
      Reserver.new(UserConfig[:ahiruyaki_stamina_recover_time]) do
        Plugin.call :ahiruyaki_stamina_full if stamina >= stamina_max end
    else
      rewind_stamina end
    activity :ahiruyaki_info, "スタミナ #{stamina.to_i}/#{stamina_max} 全回復時刻 #{UserConfig[:ahiruyaki_stamina_recover_time]}" end

  on_ahiruyaki_stamina_recover do |stamina|
    stamina_value_label.text = '%i'.freeze % stamina
    stamina_progressbar.fraction = stamina.to_f / stamina_max
    rewind_stamina end

  on_ahiruyaki_stamina_full do
    stamina_value_label.text = '%i'.freeze % stamina
   activity :ahiruyaki_info, "スタミナが全回復しました" end

  on_ahiruyaki_bake do
    expend_stamina(10) do
      Service.primary.post message: '#あひる焼き'.freeze
      Plugin.call :ahiruyaki_baked
      add_experience 10, 'あひるを焼いた。' end end

  # 魔法石所持数の表示を更新
  on_ahiruyaki_stone_changed do |stone|
    stone_label.text = stone.to_s end

  command(:ahiruyaki_bake,
          name: 'あひるを焼く',
          condition: lambda{ |opt| stamina >= 1 },
          visible: true,
          role: :timeline) do |opt|
    Plugin.call :ahiruyaki_bake end

  command(:ahiruyaki_bake_well_done,
          name: 'あひるを焼く（強火）',
          condition: lambda{ |opt| stamina >= stamina_max and rank >= 20 },
          visible: true,
          role: :timeline) do |opt|
    expend_stamina(stamina) do
      Service.primary.post(message: "#あひる焼き\n\nhttp://d250g2.com".freeze).next do |message|
        notice "bake well done: #{message.inspect}"
        strong_fire << message.id end
      Plugin.call :ahiruyaki_baked end end

  def rewind_stamina
    expect = stamina + 1
    since = Plugin::Ahiruyaki::STAMINA_RECOVER_SEC - ((Time.now.to_i - UserConfig[:ahiruyaki_stamina_recover_time].to_i) % Plugin::Ahiruyaki::STAMINA_RECOVER_SEC)
    Reserver.new(since) do
      if (stamina - expect).abs <= 1.0
        Plugin.call(:ahiruyaki_stamina_recover, expect) end end end

  def stamina
    [stamina_nocap, stamina_max].min end

  def stamina_nocap
    stamina_max - (UserConfig[:ahiruyaki_stamina_recover_time] - Time.new) / Plugin::Ahiruyaki::STAMINA_RECOVER_SEC end

  # スタミナ値を _expend_ だけ消費してブロック内を実行する。ブロックの実行結果を返す。
  # スタミナが足りない場合はブロックを実行せずnilを返す。
  def expend_stamina(expend)
    if stamina >= expend
      result = yield
      if stamina >= stamina_max
        UserConfig[:ahiruyaki_stamina_recover_time] = Time.new + expend * Plugin::Ahiruyaki::STAMINA_RECOVER_SEC
      else
        UserConfig[:ahiruyaki_stamina_recover_time] += expend * Plugin::Ahiruyaki::STAMINA_RECOVER_SEC end
      Plugin.call :ahiruyaki_stamina_changed, stamina
      result end end

  def stamina_max
    9 + rank end

  def add_experience(increase, flash)
    rank_before = rank
    UserConfig[:ahiruyaki_exp] += increase
    rank_after = rank
    if rank_before < rank_after
      activity :ahiruyaki, "#{flash} #{increase.to_i} 経験値獲得\n\nランクアップ！\nランクが#{rank_after}になりました\nスタミナが#{stamina_max}になりました\nスタミナが全回復しました"
      Plugin.call(:ahiruyaki_rankup, rank_after)
    else
      activity :ahiruyaki, "#{flash} #{increase.to_i} 経験値獲得"
      exp_progressbar.fraction = (UserConfig[:ahiruyaki_exp] - exp()).to_f / (exp(rank+1) - exp())
    end
  end

  def rank
    Plugin::Ahiruyaki::RANK_TABLE.with_index.find{ |exp, _|
      UserConfig[:ahiruyaki_exp] < exp }[1] + 1 end

  # ランク _rank に達するために必要な経験値を返す
  def exp(_rank=rank)
    if _rank == 1
      0
    else
      Plugin::Ahiruyaki::RANK_TABLE.take(_rank - 1).last end end

  def stone
    (UserConfig[:ahiruyaki_stone] || 0).to_i end

  # 魔法石を _expend_ だけ消費してブロック内を実行する。ブロックの実行結果を返す。
  # 魔法石が足りない場合はブロックを実行せずnilを返す。
  def expend_stone(expend)
    if stone >= expend
      modified = stone - expend
      UserConfig[:ahiruyaki_stone] = modified
      result = yield
      Plugin.call :ahiruyaki_stone_changed, modified
      result end end

  def add_stone(increase, flash)
    if 0 < increase.to_i
      UserConfig[:ahiruyaki_stone] = stone + increase.to_i
      activity :ahiruyaki, "#{flash ? flash + "\n" : ""}魔法石を #{increase.to_i}個手に入れた！"
      Plugin.call(:ahiruyaki_stone_changed, stone) end end

### Widgets

  # 現在のランクを表示するラベル
  # ==== Return
  # Gtk::Label ランクを表示しているラベル
  def rank_label
    @rank_label ||= Gtk::Label.new() end

  # 現在のスタミナ値を示すプログレスバー
  # ==== Return
  # progressbar
  def exp_progressbar
    @exp_progressbar ||= Gtk::ProgressBar.new()
                       .set_fraction(0.0)
                       .set_orientation(Gtk::ProgressBar::LEFT_TO_RIGHT)
  end

  # 現在のスタミナ値を表示するラベル
  # ==== Return
  # Gtk::Label ランクを表示しているラベル
  def stamina_value_label
    @stamina_value_label ||= Gtk::Label.new() end

  # スタミナ値の最大を表示するラベル
  # ==== Return
  # Gtk::Label ランクを表示しているラベル
  def stamina_max_label
    @stamina_max_label ||= Gtk::Label.new() end

  # 現在のスタミナ値を示すプログレスバー
  # ==== Return
  # progressbar
  def stamina_progressbar
    @stamina_progressbar ||= Gtk::ProgressBar.new()
                           .set_fraction(0.0)
                           .set_orientation(Gtk::ProgressBar::LEFT_TO_RIGHT) end

  # 魔法石の数を表示するラベル
  # ==== Return
  # Gtk::Label ランクを表示しているラベル
  def stone_label
    @stone_label ||= Gtk::Label.new() end

  container = Gtk::VBox.new
              .closeup(Gtk::Table.new(6, 2)
                        .attach(Gtk::Label.new('経験値').right, 0,1,0,1)
                        .attach(exp_progressbar, 1,2,0,1)
                        .attach(Gtk::Label.new('ランク').right, 2,3,0,1)
                        .attach(rank_label.left, 3,4,0,1)
                        .attach(Gtk::Label.new('魔法石').right, 4,5,0,1)
                        .attach(stone_label.left, 5,6,0,1)
                        .attach(Gtk::Label.new('スタミナ').right, 0,1,1,2)
                        .attach(stamina_progressbar, 1,2,1,2)
                        .attach(Gtk::HBox.new()
                                 .closeup(stamina_value_label)
                                 .closeup(Gtk::Label.new('/'))
                                 .closeup(stamina_max_label).center, 2,4,1,2)
                      )
              .add(Gtk::ScrolledWindow.new
                    .add_with_viewport(Gtk::VBox.new.tap{|c|
                                         Plugin.filtering(:ahiruyaki_unit, []).first.each(&c.method(:closeup))}))

  tab(:ahiruyaki_status, "あひる焼き") do
    set_icon File.join(__dir__, 'icon.png')
    nativewidget container
  end
end
