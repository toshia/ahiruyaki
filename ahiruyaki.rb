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
  PATTERN = Regexp.union(%w<あひる焼き ahiruyaki>)

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
                           .set_orientation(Gtk::ProgressBar::LEFT_TO_RIGHT)
  end

  def rank_widget
    @rank_widget ||= Gtk::HBox.new.tap do |container|
      container
        .closeup(Gtk::Label.new('あひる焼きランク'))
        .add(exp_progressbar)
        .closeup(rank_label) end end

  def stamina_widget
    @stamina_widget ||= Gtk::HBox.new.tap do |container|
      container
        .closeup(Gtk::Label.new('スタミナ'))
        .add(stamina_progressbar)
        .closeup(stamina_value_label)
        .closeup(Gtk::Label.new('/'))
        .closeup(stamina_max_label) end end
end

Plugin.create(:ahiruyaki) do

  UserConfig[:ahiruyaki_stamina_recover_time] ||= Time.new
  UserConfig[:ahiruyaki_exp] ||= 0
  strong_fire = Set.new()

  defactivity "ahiruyaki", 'あひる焼き'
  defactivity "ahiruyaki_info", 'あひる焼き（情報）'

  tab(:ahiruyaki_status, "あひる焼き") do
    #set_icon
    nativewidget Gtk::VBox.new
                  .closeup(Plugin::Ahiruyaki.rank_widget)
                  .closeup(Plugin::Ahiruyaki.stamina_widget)
  end

  Delayer.new do
    Plugin::Ahiruyaki.rank_label.text = rank.to_s
    Plugin::Ahiruyaki.stamina_value_label.text = '%i'.freeze % stamina
    Plugin::Ahiruyaki.stamina_max_label.text = stamina_max.to_s
    Plugin::Ahiruyaki.stamina_progressbar.fraction = stamina.to_f / stamina_max
    Plugin::Ahiruyaki.exp_progressbar.fraction = (UserConfig[:ahiruyaki_exp] - exp()).to_f / (exp(rank+1) - exp())
    rewind_stamina
  end

  on_appear do |messages|
    messages.lazy.reject(&:from_me?).select{ |message|
      message[:created] > defined_time
    }.select{ |message|
      Plugin::Ahiruyaki::PATTERN.match(message.to_s)
    }.each do |baking_message|
      expend_stamina(1) do
        baking_message.favorite
        add_experience 1, "#{baking_message.user[:name]} さんがあひるを焼いた。" end end
  end

  on_mention do |service, messages|
    messages.lazy.select(&:has_receive_message?).select{ |message|
      message[:created] > defined_time
    }.select{ |message|
      Plugin::Ahiruyaki::AHIRU_ID == message.user.id
    }.select { |message|
      message.replyto_source.from_me?
    }.select { |message|
      Plugin::Ahiruyaki::PATTERN.match(message.replyto_source.to_s)
    }.each do |message|
      if strong_fire.include? message.replyto_source.id
        add_experience [1, rank ** 1.5].max, "あひるを焼くなと言われた。\n強火ボーナス！"
        strong_fire.delete(message.id)
      else
        add_experience [1, rank].max, "あひるを焼くなと言われた。" end end
  end

  on_ahiruyaki_rankup do |after_rank|
    if after_rank == rank
      UserConfig[:ahiruyaki_stamina_recover_time] = Time.new
      Plugin.call :ahiruyaki_stamina_changed, stamina
      Plugin::Ahiruyaki.rank_label.text = after_rank.to_s
      Plugin::Ahiruyaki.stamina_max_label.text = stamina_max.to_s
      Plugin::Ahiruyaki.exp_progressbar.fraction = (UserConfig[:ahiruyaki_exp] - exp()).to_f / (exp(rank+1) - exp())
    end
  end

  on_ahiruyaki_stamina_changed do |_stamina|
    Plugin::Ahiruyaki.stamina_value_label.text = '%i'.freeze % stamina
    Plugin::Ahiruyaki.stamina_progressbar.fraction = stamina.to_f / stamina_max
    if _stamina >= stamina_max
      Reserver.new(UserConfig[:ahiruyaki_stamina_recover_time]) do
        Plugin.call :ahiruyaki_stamina_full if stamina >= stamina_max end
    else
      rewind_stamina end
    activity :ahiruyaki_info, "スタミナ #{stamina.to_i}/#{stamina_max} 全回復時刻 #{UserConfig[:ahiruyaki_stamina_recover_time]}" end

  on_ahiruyaki_stamina_recover do |stamina|
    Plugin::Ahiruyaki.stamina_value_label.text = '%i'.freeze % stamina
    Plugin::Ahiruyaki.stamina_progressbar.fraction = stamina.to_f / stamina_max
    rewind_stamina end

  on_ahiruyaki_stamina_full do
    Plugin::Ahiruyaki.stamina_value_label.text = '%i'.freeze % stamina
   activity :ahiruyaki_info, "スタミナが全回復しました" end

  on_ahiruyaki_bake do
    expend_stamina(10) do
      Service.primary.post message: '#あひる焼き'.freeze
      Plugin.call :ahiruyaki_baked
      add_experience 10, 'あひるを焼いた。' end end

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
      Plugin::Ahiruyaki.exp_progressbar.fraction = (UserConfig[:ahiruyaki_exp] - exp()).to_f / (exp(rank+1) - exp())
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

end
