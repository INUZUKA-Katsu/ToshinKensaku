require 'json'
require 'kconv'
require "net/https"
require 'open-uri'
require 'aws-sdk-s3'
require 'parallel'
require 'concurrent'
require "#{__dir__}/set_each_range_text"

STDOUT.sync = true
Encoding.default_external = "utf-8"

class Hash
  def key_to_sym()
    new_h = Hash.new
    self.keys.each do |k|
      new_h[k.to_sym]=self[k]
    end
    new_h
  end
end
class S3Client
  attr_reader :bucket
  def initialize
    @resource = Aws::S3::Resource.new(
      :region => 'us-east-1',
      :access_key_id   => ENV['AWS_ACCESS_KEY_ID'],
      :secret_access_key => ENV['AWS_SECRET_ACCESS_KEY']
    )
    @bucket = @resource.bucket('storgae-for-herokuapp')
  end
  def read(file_name)
    @bucket.object("toshin/"+file_name).get.body.read.toutf8
  end
  def write(file_name,str)
    @bucket.put_object(key: "toshin/"+file_name, body: str)
  end
  def exist?(file_name)
    @bucket.object("toshin/"+file_name).exists?
  end
  def remove(file_name)
    @bucket.object("toshin/"+file_name).delete
  end
  def get_list
    res = []
    @bucket.objects(prefix: "toshin/").each do |obj|
      res << obj.key if obj.key.include? ".txt"
    end
    res
  end
  # 起動時にtmpフォルダを確認し、不足するファイルをダウンロードする。
  def fill_tmp_folder
    s3_files = get_list.map{|f| f.sub("toshin/","")}
    tmp_files = Dir.glob('./tmp/*.txt').map{|f| f.sub(/.*tmp\//,"")}
    # スレッド数を5に制限したプールを作成
    pool = Concurrent::ThreadPoolExecutor.new(max_threads: 5)
    (s3_files-tmp_files).each do |f|
      pool.post do
        File.write("./tmp/"+f,read(f))
        sleep 0.5
      end
    end
    # プールが終了するのを待つ
    pool.shutdown
    pool.wait_for_termination
    #thread = []
    #(s3_files-tmp_files).each do |f|
    #  thread << Thread.new do
    #    File.write("./tmp/"+f,read(f))
    #    sleep 0.05
    #  end
    #end
    #thread.each(&:join)
    set_each_range_text
  end
end
def postData_arrange(param)
  #p param
  joken = Hash.new
  j_str = Hash.new
  if param["searchQuery"]!=""
    joken[:freeWordRange] = ""
    joken[:freeWord] = param["searchQuery"].split(/\s+|　+/)
    joken[:freeWordType] = param["searchType"]
    range = "答申全体"
  end
  if param["ketsuronSearchQuery"]!=""
    joken[:freeWordRange] = "ketsuron"
    joken[:freeWord] = param["ketsuronSearchQuery"].split(/\s+|　+/)
    joken[:freeWordType] = param["ketsuronSearchType"]
    range = "審査会の結論"
  end
  if param["seikyuninSearchQuery"]!=""
    joken[:freeWordRange] = "seikyunin"
    joken[:freeWord] = param["seikyuninSearchQuery"].split(/\s+|　+/)
    joken[:freeWordType] = param["seikyuninSearchType"]
    range = "審査請求人の意見"
  end
  if param["jisshikikanSearchQuery"]!=""
    joken[:freeWordRange] = "jisshikikan"
    joken[:freeWord] = param["jisshikikanSearchQuery"].split(/\s+|　+/)
    joken[:freeWordType] = param["jisshikikanSearchType"]
    range = "実施機関の説明"
  end
  if param["shinsakaiSearchQuery"]!=""
    joken[:freeWordRange] = "shinsakai"
    joken[:freeWord] = param["shinsakaiSearchQuery"].split(/\s+|　+/)
    joken[:freeWordType] = param["shinsakaiSearchType"]
    range = "審査会の判断"
  end
  if param["shinsakailastSearchQuery"]!=""
    joken[:freeWordRange] = "shinsakailast"
    joken[:freeWord] = param["shinsakailastSearchQuery"].split(/\s+|　+/)
    joken[:freeWordType] = param["shinsakailastSearchType"]
    range = "審査会の判断の結論部分"
  end
  if joken[:freeWordType]=="and"
    j_str[range]= joken[:freeWord].map{|w| '"'+w+'"'}.join(" かつ ")
  elsif joken[:freeWordType]=="or"
    j_str[range]= joken[:freeWord].map{|w| '"'+w+'"'}.join(" 又は ")
  end
  
  if param["johoKokai"]=="on" and param["kojinjohoHogo"]==nil
    joken[:jorei] = "情報公開"
    j_str["条例"] = "情報公開"
  elsif param["johoKokai"]==nil and param["kojinjohoHogo"]=="on"
    joken[:jorei] = "個人情報"
    j_str["条例"] = "個人情報"
  elsif param["johoKokai"]==nil and param["kojinjohoHogo"]==nil
    joken[:jorei] = ""
    j_str["条例"] = "なし"
  end
  
  joken[:seikyu] = ""
  seikyu = []
  if param["kaijiSeikyu"]=="on"
    joken[:seikyu] += "開示請求"
    seikyu << "開示請求"
  end
  if param["teiseiSeikyu"]=="on"
    joken[:seikyu] += "訂正請求"
    seikyu << "訂正請求"
  end
  if param["teishiSeikyu"]=="on"
    joken[:seikyu] += "利用停止請求"
    seikyu << "利用停止請求"
  end
  j_str["請求"] = seikyu.join(",")
  
  bukai = []
  if param["bukai"]!=""
    joken[:bukai] = param["bukai"]
    bukai << joken[:bukai]
  end
  if param["bukaiSearchQuery"]!=""
    joken[:bukaiQuery] = param["bukaiSearchQuery"].split(/\s+|　+/)
    bukai += joken[:bukaiQuery]
  end
  j_str["部会"] = bukai.join(",") unless bukai==[]

  if param["iinSearchQuery"]!=""
    joken[:iinQuery] = param["iinSearchQuery"].split(/\s+|　+/)
    j_str["審査会委員"] = joken[:iinQuery].join(",")
  end
  
  kikan = []
  if param["jisshiKikan"]!=""
    joken[:kikan] = param["jisshiKikan"]
    kikan << joken[:kikan]
  end
  if param["jisshiaKikanQuery"]!=""
    joken[:kikanQuery] = param["jisshiaKikanQuery"].split(/\s+|　+/)
    kikan += joken[:kikanQuery]
  end
  j_str["実施機関"]=kikan.join(",") unless kikan==[]

  if param["reportDateFromYear"]!=""
    gen   = param["reportDateFromEra"]
    y     = param["reportDateFromYear"]
    m     = param["reportDateFromMonth"]
    d     = param["reportDateFromDate"]
    range = param["reportDateRange"]
    if gen=="heisei"
      yyyy = y.to_i+1988
      j_str["答申日"] = "平成#{y}年"
    else
      yyyy = y.to_i+2018
      j_str["答申日"] = "令和#{y}年"
    end
    if m==""
      yyyymm = yyyy.to_s+"01"
      j_str["答申日"]+="1月"
    else
      yyyymm = yyyy.to_s+("0"+m)[-2,2]
      j_str["答申日"]+="#{m}月"
    end
    if d==""
      yyyymmdd = yyyymm.to_s+"01"
      j_str["答申日"]+="1日"
    else
      yyyymmdd = yyyymm.to_s+("0"+d)[-2,2]
      j_str["答申日"]+="#{d}日"
    end
    if range=="kan" or range=="go"
      joken[:yyyymmdd] = {:from => yyyymmdd}
      j_str["答申日"]+=" 〜 "
    elsif range=="zen"
      joken[:yyyymmdd] = {:to => yyyymmdd}
      j_str["答申日"] = " 〜 " + j_str["答申日"]
    elsif range==""
      joken[:yyyymmdd] = yyyymmdd
    end
  end

  if param["reportDateToYear"]!=""
    range = param["reportDateRange"]
    # rangeが "〜" 以外のときは右側の日付が入力されていても無視する。
    if range=="kan"
      gen   = param["reportDateToEra"]
      y     = param["reportDateToYear"]
      m     = param["reportDateToMonth"]
      d     = param["reportDateToDate"]
      if gen=="heisei"
        yyyy = y.to_i+1988
        j_str["答申日"] += "平成#{y}年"
      else
        yyyy = y.to_i+2018
        j_str["答申日"] += "令和#{y}年"
      end
      if m==""
        yyyymm = yyyy.to_s+"12"
        j_str["答申日"]+="12月"
      else
        yyyymm = yyyy.to_s+("0"+m)[-2,2]
        j_str["答申日"]+="#{m}月"
      end
      if d==""
        yyyymmdd = yyyymm.to_s+"1"
        j_str["答申日"]+="1日"
      else
        yyyymmdd = yyyymm.to_s+("0"+d)[-2,2]
        j_str["答申日"]+="#{d}日"
      end
      joken[:yyyymmdd][:to] = yyyymmdd
    end
  end
  if param["reportNoFromNo"]!=""
  	num = param["reportNoFromNo"]
    range = param["reportNoRange"]
    
    if range=="go" or range=="kan"
      joken[:num]={:from => num}
      j_str["答申番号"] = "第#{num}号〜"
    
    elsif range=="zen"
      joken[:num]={:to => num}
      j_str["答申番号"] = "〜第#{num}号"
    else
      joken[:num]=num
      j_str["答申番号"] = "第#{num}号"
    end
  end
  if param["reportNoToNo"]!=""
  	num = param["reportNoToNo"]
    range = param["reportNoRange"]
    if range=="kan"
      joken[:num][:to]=num
      j_str["答申番号"] += "第#{num}号"
    end
  end
  [ joken, j_str ]
end
def getData_arrange(query_string)
  joken={}
  j_str={}
  key_word = Hash[URI.decode_www_form(query_string)]["key_word"]
  joken[:seikyu] = "開示請求"
  joken[:freeWordRange] = "shinsakai"
  joken[:freeWord] = key_word.split(/\s+|　+/)
  joken[:freeWordType]="and"
  j_str["審査会の判断"]=joken[:freeWord].map{|w| '"'+w+'"'}.join(" かつ ")
  j_str["請求"]="開示請求"
  [ joken, j_str ]
end

class Toshin
  def initialize
    @s3 = S3Client.new
    @midashi = JSON.parse(@s3.read("bango_hizuke_kikan.json"), symbolize_names: true)
  end
  #フリーワード以外の条件から対象ファイルを絞り込む。
  def search(joken) #jokenはハッシュ
    selected = @midashi
    if joken.keys.include? :jorei
       selected = selected.select{|h|
         #p "h[:jorei].include?(joken[:jorei]) => " + h[:jorei] + " include? " + joken[:jorei]
         joken[:jorei].include?(h[:jorei])
       }
    end
    p :s1
    p selected.size
    if joken.keys.include? :seikyu and joken[:seikyu] != "開示請求訂正請求利用停止請求"
       selected = selected.select{|h|
         #p "joken[:seikyu].include?(h[:seikyu]) => " + joken[:seikyu] + " include? " + h[:seikyu]
         h[:seikyu]!="" and joken[:seikyu].include?(h[:seikyu])
       }
    end
    p :s2
    p selected.size

    if joken.keys.include? :num
       if joken[:num].class==String
         selected = selected.select{|h| h[:num_array].include?(joken[:num])}
       elsif joken[:num].class==Hash
         j = joken[:num]
         if j.keys.size==2
           a = (j[:from]..j[:to]).to_a
           selected = selected.select{|h| (h[:num_array] & a).size>0 }
         elsif j.keys[0]==:from
           selected = selected.select{|h| j[:from].to_i <= h[:num_array].max.to_i }
         elsif j.keys[0]==:to
           selected = selected.select{|h| j[:to].to_i >= h[:num_array].min.to_i }
         end
       end
    end
    p :s3
    p selected.size

    if joken.keys.include? :bango
       selected = selected.select{|h| h[:bango].include?(joken[:bango])}
    end
    p :s4
    p selected.size

    if joken.keys.include? :yyyymmdd
       if joken[:yyyymmdd].class==String
         selected = selected.select{|h| h[:yyyymmdd].include?(joken[:yyyymmdd])}
       elsif joken[:yyyymmdd].class==Hash
         j = joken[:yyyymmdd]
         if j.keys.size==2
           selected = selected.select{|h| h[:yyyymmdd].between?(j[:from],j[:to])}
         elsif j.keys[0]==:from
           selected = selected.select{|h| j[:from] <= h[:yyyymmdd]}
         elsif j.keys[0]==:to
           selected = selected.select{|h| h[:yyyymmdd] <= j[:to]}
         end
       end
    end
    p :s5
    p selected.size

    if joken.keys.include? :toshinbi
       selected = selected.select{|h| h[:toshinbi].include?(joken[:toshinbi])}
    end
    p :s6
    p selected.size

    if joken.keys.include? :kikan
       selected = selected.select{|h| h[:jisshikikan].include?(joken[:kikan])}
    end
    p :s7
    p selected.size

    if joken.keys.include? :kikanQuery
       joken[:kikanQuery].each do |k|
         selected = selected.select{|h| h[:jisshikikan].include?(k)}
       end
    end
    p :s8
    p selected.size

    if joken.keys.include? :bukai
       selected = selected.select{|h| h[:bukai].include?(joken[:bukai])}
    end
    p :s9
    p selected.size

    if joken.keys.include? :bukaiQuery
       ary = []
       selected_ary = joken[:bukaiQuery].map{|bukai| selected.select{|h| h[:bukai].include? bukai}}
       selected_ary.each do |selected|
         ary =  ary | selected
       end
       selected = ary
    end
    p :s10
    p selected.size

    if joken.keys.include? :iinQuery
       ary = []
       selected_ary = joken[:iinQuery].map{|iin| selected.select{|h| h[:iin].include? iin}}
       selected_ary.each do |selected|
         ary =  ary | selected
       end
       selected = ary
    end
    selected
  end
  def get_url(joken)
  	search(joken).map{|h| h[:url]}
  end
  def get_bango(joken="")
    if joken == ""
      @midashi.map{|h| h[:bango]}
    else
      search(joken).map{|h| h[:bango]}
    end
  end
  def get_toshinbi(bango)
    @midashi.find{|h| h[:bango]==bango}[:toshinbi]
  end
  def get_jisshikikan(bango)
    @midashi.find{|h| h[:bango]==bango}[:jisshikikan]
  end
  def get_bukai(bango)
    @midashi.find{|h| h[:bango]==bango}[:bukai]
  end
  def get_file_name(bango)
    @midashi.find{|h| h[:bango]==bango}[:file_name]
  end
  def get_kenmei(bango)
    @midashi.find{|h| h[:bango]==bango}[:kenmei]
  end
  def get_url(bango)
    @midashi.find{|h| h[:bango]==bango}[:url]
  end

  #########################################
  #   メイン関数（config.ruから呼び出される）
  #########################################
  def get_hinagata_data(joken)
    if joken.keys.include? :freeWord
      selected = freeWord_search(joken)
    else
      selected = search(joken)
    end
    res = Hash.new
    p "selected = freeWord_search(joken)"
    p 'selected.size: ' + selected.size.to_s
    selected.each do |h|
      bango = h[:bango]
      h.delete(:bango)
      h.delete(:yyyymmdd)
      h.delete(:file_name)
      h.delete(:iin)
      h.delete(:jorei)
      h.delete(:seikyu)
      res[bango] = h
    end
    res   # config.ruに返す
  end

  def freeWord_search(joken)
    def ripgrep(file_name_array, word_array, type)
      files = file_name_array.map{|file_name| "#{__dir__}/tmp/#{file_name}"}.join(' ')
      #puts files
      if type == 'or'
        search_terms = word_array.join('|')
        rg_command = "rg --no-ignore --files-with-matches -l '#{search_terms}' #{files}"
      elsif type == 'and'
        if word_array.size==1
          search_terms = word_array[0]
          rg_command = "rg --no-ignore --files-with-matches -l '#{search_terms}' #{files}"
        else
          search_terms1 = word_array[0]
          search_terms2 = word_array[1..-1].map{|w| "xargs rg -l '#{w}'"}.join(" | ")
          rg_command = "rg --no-ignore --files-with-matches -l '#{search_terms1}' #{files} | #{search_terms2}"
        end
      end
      matching_file_path_array = `#{rg_command}`.split("\n") #.select{|f| f.match(/答申/)}
    end
    def text_range(joken)
      case joken[:freeWordRange]
      when ""             ;  nil
      when "ketsuron"     ;  "審査会の結論.*?(?=((異議)?申立て|審査請求|申出)の趣旨)"
      when "jisshikikan"  ;  "理由説明要旨.*?(?=((本件処分|決定|回答)等?に対する|申\立人の|審査請求人の)意見)"
      when "seikyunin"    ;  "((本件処分|決定|回答)等?に対する|申\立人の|審査請求人の)意見.*?(?=審査会の判断)"
      when "shinsakai"    ;  '審査会の判断.*'
      when "shinsakailast";  '(結( |　)+論|[）)]( |　)*結論|[0-9０-９]( |　)*結論)(.*?(^( |　)*別表|別表[0-9０-９]*( |　)*$|別( |　)+表|審査会の経過)|.*)'
      else  nil
      end
    end
    def reg_pattern(word_array)
      # 検索語が複数の時は、"[^\n]*(検索語1|検索語2|検索語3).*(検索語1|検索語2|検索語3).*?\n"
      # という正規表現をつくる。  
        "[^\n]{0,100}(#{word_array.join("|")})(.*(#{word_array.join("|")}))?[^\n]{0,100}\n?"
    end
    #************** 答申のテキストから該当箇所を切り出す *****************
    def exec_search(str,word_array,type)
      #審査会の判断など指定された範囲を切り出す。
      #if range_joken and ans = str.match(/#{range_joken}/m)
      #  str = ans[0]
      #end
      #全角数字を半角に変換
      str = str.tr("０-９","0-9")
      #指定範囲に検索語句が含まれるか調べ、含まれない場合は除外
      ########## ripgrepで仕分け済み ###########
      #if range_joken
      #  if type=='or'
      #    #マッチする語句が一つもなければそのファイルは終了
      #    res = nil
      #    word_array.each do |k|
      #      res = true if str.match(/#{k}/m)
      #    end
      #    return nil unless res
      #    #return nil unless str.match(/#{word_array.join('|')}/)
      #  else
      #    #マッチしない語句が一つでもあればそのファイルは終了
      #    word_array.each do |k|
      #      return nil unless str.match(/#{k}/m)
      #    end
      #    #return nil unless str.match(/#{word_array.map{|w| "(?=.*#{w})"}.join()}/)
      #  end
      #end
      #*** 各語句の前後200字を切り出し、つなげる ***
      begin
      #p "[^\n]{0,200}#{word_array.join('|')}[^\n]{0,200}\n?"
        range_array = str.scan(/[^\n]{0,200}#{word_array.join("|")}[^\n]{0,200}\n?/m).
                      map do |s|
                        s.gsub!(/#{word_array.join("|")}/m,'<strong>\&</strong>')
                        s.chomp
                      end
        str = range_array.join("<br><br>")
        str
      rescue
        #p reg_pattern(word_array)
        #p str
      end
    end

    #***** ここから、検索の流れに入る。*****

    #*** 下準備 ***
    word_array,type = joken[:freeWord],joken[:freeWordType]
    #puts "range_joken : #{range_joken}"
    #ユーザーが正規表現を使いやすくする。”\”は取り扱いが難しいので"¥"が使えるようにする。
    word_array.map!{|w| w.gsub('¥',"\\")}
    #検索語に含まれる数字をすべて半角に変換する。
    word_array.map!{|w| w.tr("０-９","0-9")}

    #******* フリーワード以外の条件でmidashi配列を絞り込む。*******
    selected = search(joken)
    puts "答申ファイル数は #{@midashi.size} 件"
    puts "search => 対象は #{selected.size} 件"
    
    #******* ripgrepで対象ファイルを絞り込む。*******************
    if joken[:freeWordRange]==""
      file_name_array = selected.map{|h| h[:file_name]}
    else
      #範囲条件があるとき
      file_name_array = selected.map{|h|
        if h[:file_name]
          h[:file_name].sub(/\.txt/,"#{joken[:freeWordRange]}.txt")
        else
          p "h[:file_name]=nil"
          p h
        end 
      }
    end
    file_path_array = ripgrep(file_name_array, word_array, type)
    puts "ripgrep => 対象は #{file_path_array.size} 件"

    file_path_array.each{|path| p path if path.size>100}
    puts
    puts

    #p "file_path_array ↓"
    #p file_path_array
    #****** 対象ファイルによってmidashi配列を絞り込む *********
    #file_name_array = file_path_array.map{|path| File.basename(path)}
    #selected.select!{|h| file_name_array.include? h[:file_name]}
    
    #******* 対象ファイルから該当箇所を切り出す。******************
    #res={}
    #selected = selected.each do |h|
    #  path = "#{__dir__}/tmp/#{h[:file_name]}"
    #  str = File.read(path).encode("UTF-8", :invalid => :replace)
    #  matched_range = exec_search(str,word_array,type,range_joken)
    #  if matched_range
    #    h[:matched_range] = matched_range
    #  end
    #end.select{|h| h.keys.include?(:matched_range)}
    ##puts selected
    #return selected
if 1==1
    #results = Parallel.map(selected, in_processes: Etc.nprocessors) do |h|
    results = Parallel.map(file_path_array, in_processes: Etc.nprocessors) do |path|
      #p "処理中: PID: #{Process.pid}"
      retry_num = 0
      begin
        #path = "#{__dir__}/tmp/#{h[:file_name]}"
        str = File.read(path).encode("UTF-8", :invalid => :replace)
      rescue
        if File.exist?(path)
          retry_num += 1
          if retry_num < 5
            p File.basename(path) + "の読み込みエラー ⇒ リトライします!(#{retry_num}回目)"
            retry
          else
            p File.basename(path) + "を読み込めませんでした!"
          end
        else
          p File.basename(path) + "の読み込みエラー ファイルがありません!"
        end
        str = " "
      end
      matched_range = exec_search(str,word_array,type)
      if matched_range
        #h.merge({:matched_range => matched_range})  # `merge` を使って新しいハッシュを返す
        file_name_origin = File.basename(path).sub(/(.*号(まで)?)(.+?)\.txt/,'\1.txt')
        begin
        selected.find{|h| h[:file_name] == file_name_origin}.
                          merge({:matched_range => matched_range})
        rescue =>e
          p e.message
        end
      else
        nil
      end
    end
    File.write("parallel_result.json", JSON.generate(results)) #debug用
    return results.compact # nilを除外
else
    #Herokuのリソースエラーにならないようにスレッド数を200に制限.
    res=[]
    n = (selected.size/200.0).ceil
    n.times do |i|
      thread = []
      st = i*200
      selected[st,200].each do |h|
        thread << Thread.new do
          file_name = h[:file_name]
          retry_num = 0
          begin
            str = File.read("./tmp/"+file_name).encode("UTF-8", :invalid => :replace)
          rescue
            if File.exist?("./tmp/"+file_name)
              retry_num += 1
              if retry_num < 5
                p file_name + "の読み込みエラー ⇒ リトライします!(#{retry_num}回目)"
                retry
              else
                p file_name + "を読み込めませんでした!"
              end
            else
              p file_name + "の読み込みエラー ファイルがありません!"
            end
            str = " "
          end
          matched_range = exec_search(str,word_array,type,range_joken)
          if matched_range
            h[:matched_range] = matched_range
            res << h
          end
        end
      end
      thread.each(&:join)
    end
    #File.write("thread_result.json", JSON.generate(res))  #debug用
    res
end
  end
end

#検索結果から検索画面に戻る際の処理
def get_index(param)
  str = File.read("index.html")
  return str unless param.keys.include? "joken"
  h = JSON.parse(param["joken"])
  ["johoKokai","kojinjohoHogo","kaijiSeikyu","teiseiSeikyu","teishiSeikyu"].each do |k|
    if h.keys.include? k
      str.sub!(/(#{k}.*)( checked="checked")?( class="checkbox">)/,'\1 checked="checked"\3')
    else
      str.sub!(/(#{k}.*?) checked="checked"/,'\1')
    end
  end
  h.keys.each do |k|
    case k
    when "searchType","ketsuronSearchType","seikyuninSearchType","jisshikikanSearchType","shinsakaiSearchType","shinsakailastSearchType"
      if h[k]=="or"
        #p k
        str.sub!(/("#{k}" value="and") checked="checked"/, '\1')
        str.sub!(/("#{k}" value="or")/, '\1 checked="checked"')
        #p str.match(/"#{k}" value="or".*/)[0]
      end
    when "bukai","jisshiKikan","reportDateFromEra","reportDateToEra","reportDateRange","reportNoRange"
      str.sub!(/.*#{k}.*?#{h[k]}"/m, '\0 selected') if h[k]!=""
    when
      str.sub!(/"#{k}"\s+value=""/, k+' value="'+h[k]+'"')
    end
  end
  str
end

#toshin=Toshin.new
# toshin.get_bango({:num => {:from => "1500",:to => "1700"},:iin=>"藤原"})
#h=toshin.get_hinagata_data({:num => {:from => "150",:to => "2500"}})
#h=toshin.get_hinagata_data({:freeWord => ["理由付記"],:freeWordType=>"and"})
#p h
#p h["答申第1442号から第1444号まで"]

 