require 'json'
require 'kconv'
require "net/https"
require 'open-uri'
require 'pdf-reader'

URL = "https://www.city.yokohama.lg.jp/city-info/gyosei-kansa/joho/kokai/johokokaishinsakai/shinsakai/"

def main(param)
  p param
  joken = Hash.new
  if param["searchQuery"]!=""
    joken[:freeWordRange] = ""
    joken[:freeWord] = param["searchQuery"].split(/\s+|　+/)
    joken[:freeWordType] = param["searchType"]
  end
  if param["ketsuronSearchQuery"]!=""
    joken[:freeWordRange] = "ketsuron"
    joken[:freeWord] = param["ketsuronSearchQuery"].split(/\s+|　+/)
    joken[:freeWordType] = param["ketsuronSearchType"]
  end
  if param["seikyuninSearchQuery"]!=""
    joken[:freeWordRange] = "seikyunin"
    joken[:freeWord] = param["seikyuninSearchQuery"].split(/\s+|　+/)
    joken[:freeWordType] = param["seikyuninSearchType"]
  end
  if param["jisshikikanSearchQuery"]!=""
    joken[:freeWordRange] = "jisshikikan"
    joken[:freeWord] = param["jisshikikanSearchQuery"].split(/\s+|　+/)
    joken[:freeWordType] = param["jisshikikanSearchType"]
  end
  if param["shinsakaiSearchQuery"]!=""
    joken[:freeWordRange] = "shinsakai"
    joken[:freeWord] = param["shinsakaiSearchQuery"].split(/\s+|　+/)
    joken[:freeWordType] = param["shinsakaiSearchType"]
  end
  if param["shinsakailastSearchQuery"]!=""
    joken[:freeWordRange] = "shinsakailast"
    joken[:freeWord] = param["shinsakailastSearchQuery"].split(/\s+|　+/)
    joken[:freeWordType] = param["shinsakailastSearchType"]
  end
  if param["johoKokai"]=="on" and param["kojinjohoHogo"]==nil
    joken[:jorei] = "情報公開"
  elsif param["johoKokai"]==nil and param["kojinjohoHogo"]=="on"
    joken[:jorei] = "個人情報"
    joken[:seikyu] = ""
    if param["kaijiSeikyu"]=="on"
      joken[:seikyu] += "開示請求"
    end
    if param["teiseiSeikyu"]=="on"
      joken[:seikyu] += "訂正請求"
    end
    if param["teishiSeikyu"]=="on"
      joken[:seikyu] += "利用停止請求"
    end
  end
  if param["bukai"]!=""
    joken[:bukai] = param["bukai"]
  end
  if param["bukaiSearchQuery"]!=""
    joken[:bukaiQuery] = param["bukaiSearchQuery"].split(/\s+|　+/)
  end
  if param["iinSearchQuery"]!=""
    joken[:iinQuery] = param["iinSearchQuery"].split(/\s+|　+/)
  end
  if param["jisshiKikan"]!=""
    joken[:kikan] = param["jisshiKikan"]
  end
  if param["jisshiaKikanQuery"]!=""
    joken[:kikanQuery] = param["jisshiaKikanQuery"].split(/\s+|　+/)
  end
  if param["reportDateFromYear"]!=""
    gen   = param["reportDateFromEra"]
    y     = param["reportDateFromYear"]
    m     = param["reportDateFromMonth"]
    d     = param["reportDateFromDate"]
    range = param["reportDateRange"]
    if gen=="heisei"
      yyyy = y.to_i+1988
    else
      yyyy = y.to_i+2018
    end
    if m==""
      yyyymm = yyyy.to_s+"01"
    else
      yyyymm = yyyy.to_s+("0"+m)[-2,2]
    end
    if d==""
      yyyymmdd = yyyymm.to_s+"01"
    else
      yyyymmdd = yyyymm.to_s+("0"+d)[-2,2]
    end
    if range=="kan" or range=="go"
      joken[:yyyymmdd] = {:from => yyyymmdd}
    elsif range=="zen"
      joken[:yyyymmdd] = {:to => yyyymmdd}
    elsif range==""
      joken[:yyyymmdd] = yyyymmdd
    end
  end
  if param["reportDateToYear"]!=""
    range = param["reportDateFromRange"]
    # rangeが "〜" 以外のときは右側の日付が入力されていても無視する。
    if range=="kan"
      gen   = param["reportDateToEra"]
      y     = param["reportDateToYear"]
      m     = param["reportDateToMonth"]
      d     = param["reportDateToDay"]
      if gen=="heisei"
        yyyy = y.to_i+1988
      else
        yyyy = y.to_i+2018
      end
      if m==""
        yyyymm = yyyy.to_s+"01"
      else
        yyyymm = yyyy.to_s+("0"+m)[-2,2]
      end
      if d==""
        yyyymmdd = yyyymm.to_s+"01"
      else
        yyyymmdd = yyyymm.to_s+("0"+d)[-2,2]
      end
      joken[:yyyymmdd][:to] = yyyymmdd
    end
  end
  if param["reportNoFromNo"]!=""
  	num = param["reportNoFromNo"]
    range = param["reportNoRange"]
    if range=="go" or range=="kan"
      joken[:num]={:from => num}
    elsif range=="zen"
      joken[:num]={:to => num}
    else
      joken[:num]=num
    end
  end
  if param["reportNoToNo"]!=""
  	num = param["reportNoToNo"]
    range = param["reportNoRange"]
    if range=="kan"
      joken[:num][:to]=num
    end
  end
  joken
end

class String
  def to_yyyymmdd
    ary = self.scan(/(令和|平成)(.*)年(.*)月(.*)日/)[0]
    return self unless ary
    ary[1].sub(/元/,"1") 
    case ary[0]
    when "平成"; str = (ary[1].to_i + 1988).to_s + ("0"+ary[2])[-2,2] + ("0"+ary[3])[-2,2]
    when "令和"; str = (ary[1].to_i + 2018).to_s + ("0"+ary[2])[-2,2] + ("0"+ary[3])[-2,2]
    end
    str
  end
end

def change_encoding
  Dir.chdir(__dir__)
  Dir.glob("./tmp/答申*txt").each do |f|
    str = File.read(f)
    unless Kconv.guess(str)==Kconv::UTF8
      File.write(f, str.toutf8)
    end
  end
end
#change_encoding

def make_midashi_json
  def get_bango_url_kenmei
    uri = URI.parse(URL)
    url_list = uri.read.scan(/href="(.*?\.html)">審査会答申一覧/).flatten
    host = uri.host
    
    toshin_url = {}
    toshin_kenmei = {}
    url_list.each do |url|
      uri =  URI.parse("https://"+host+url)
      ary = uri.read.scan(/href="(.*?files.*?pdf.*?<\/a><br>.*?)<\/li>/i).flatten
      ary.each do |a|
        url_num = a.scan(/(.*pdf).*(答申.*?)[\(（].*?<br>(.*)/i).flatten
        num = url_num[1].tr("０-９","0-9").match(/\d+/)[0]
        toshin_url[num] = url_num[0]
        toshin_kenmei[num] = url_num[2]
      end
    end
    [toshin_url,toshin_kenmei]
  end
  num2url,num2kenmei = get_bango_url_kenmei
  ary=[]
  Dir.chdir(__dir__)
  #textフォルダの答申テキストファイルをtmpフォルダにコピー
  FileUtils.cp(Dir.glob("text/*.txt"),"tmp")
  #市サイトのPDFとtextフォルダのテキストファイルを比較して不足するデータを取得する。
  json= File.read("text/bango_hizuke_kikan.json")
  #p json
  bango_list = JSON.parse(json).map{|data| data[0][0]}
  #p "bango_list=>"+bango_list.to_s
  current_bango_list = num2url.keys.map{|bango| bango.match(/\d+/)[0]}
  #p "current_bango_list=>"+current_bango_list.to_s
  lack_bango_list = current_bango_list - bango_list
  #p "lack_bango_list=>"+lack_bango_list.to_s
  File.write("tmp/lack_bango_list.json",JSON.generate(lack_bango_list))
  #********************************************************************
  #ここに不足分のPDFファイルをダウロードしてテキストを抽出し、テキストファイル保存する処理を付加する。
  #**********************************************************************
  Dir.glob("tmp/答申*txt").each do |f|
  	str = File.read(f).gsub(/\s|　/,"").tr("０-９","0-9")
    begin
      if ans1 = str.match(/.*様(?=横浜市情報公開・個人情報保護審査会会長|横浜市公文書公開審査会会長)/)
        item = ans1[0].scan(/（(答申第[\d-]+号.*?)）(..元?\d?\d?年\d\d?月\d\d?日).*?\d日(.*)様/).flatten
        bango,yyyymmdd,toshinbi,jisshikikan = item[0],item[1].to_yyyymmdd,item[1],item[2]        
        jisshikikan = jisshikikan.gsub(/市長|議長|水道事業管理者|病院事業管理者|交通事業管理者|選挙管理委員会委員長|人事委員会委員長|監査委員|農業委員会会長|固定資産評価審査委員会委員長|理事長/,'\0 ').gsub(/様/,', ') 
      end
      if ans2 = str.match(/[\(（回]([^\(（)回]*?部会)[\)）]/)
        bukai = ans2[1]
      else
        bukai = ""
      end
      if ans3 = str.match(/(?<=部会[\)）]).{1,50}委員.{1,8}?(?=(\-\d|\(|（|《参考》|別表|別紙))/)
        iin = ans3[0].gsub(/委員/,'\0 ')
      else
        iin = ""
      end
      if ans4 = str.match(/横浜市[^市]*?条例/)
        if ans4[0].include? "公開"
          jorei = "情報公開"
          seikyu = "開示請求"
        elsif ans4[0].include? "個人情報"
          jorei = "個人情報"
          if ans5 = str.match(/訂正決定|利用停止決定|開示決定/)
            case ans5[0]
            when "訂正決定"    ; seikyu = "訂正請求"
            when "利用停止決定" ; seikyu = "利用停止請求"
            when "開示決定"    ; seikyu = "開示請求"
            else ; seikyu = ""
            end
          else
            seikyu = ""
          end
        else
          jorei = ""
        end
      else
        jorei = ""
      end
    rescue
      p str
    end
    ary << [bango,yyyymmdd,toshinbi,jisshikikan,bukai,iin,jorei,seikyu,f]
  end
  ary = ary.sort_by{|a| a[0].match(/\d+/)[0].to_i}
  ary = ary.map do |a|
    num = a[0].match(/\d+/)[0]
    a << num2kenmei[num] << num2url[num]
  end
  ary = ary.map do |a|
     if a[0].match(/から/)
       res = a[0].match(/(\d+)号から.*?(\d+)/)
       n = []
       (res[1].to_i..res[2].to_i).each do |num|
         n << num.to_s 
       end
       a.unshift(n)
     else
       a.unshift([a[0].match(/\d+/)[0]])
     end
  end
  File.write("tmp/bango_hizuke_kikan.json",JSON.generate(ary))
  FileUtils.cp("tmp/bango_hizuke_kikan.json","text/bango_hizuke_kikan.json") #Heroku上では無効
  ary
end
#make_midashi_json

class Toshin
  def initialize
    @ary = JSON.parse(File.read("tmp/bango_hizuke_kikan.json"))
  end
  def search(joken) #jokenはハッシュ
    selected = @ary
    if joken.keys.include? :num
       if joken[:num].class==String
         selected = selected.select{|t| t[0].include?(joken[:num])}
       elsif joken[:num].class==Hash
         h = joken[:num]
         if h.keys.size==2
           a = []
           (h[:from]..h[:to]).each{|n| a<<n}
           selected = selected.select{|t| (t[0] & a).size>0 }
         elsif h.keys[0]==:from
           selected = selected.select{|t| h[:from].to_i <= t[0].max.to_i }
         elsif h.keys[0]==:to
           selected = selected.select{|t| h[:to].to_i >= t[0].min.to_i }
         end
       end
    end
    if joken.keys.include? :bango
       selected = selected.select{|t| t[1].include?(joken[:bango])}
    end
    if joken.keys.include? :yyyymmdd
       if joken[:yyyymmdd].class==String
         selected = selected.select{|t| t[2].include?(joken[:yyyymmdd])}
       elsif joken[:yyyymmdd].class==Hash
         h = joken[:yyyymmdd]
         if h.keys.size==2
           selected = selected.select{|t| (h[:from]..h[:to]).include?(t[2])}
         elsif h.keys[0]==:from
           selected = selected.select{|t| h[:from] <= t[2]}
         elsif h.keys[0]==:to
           selected = selected.select{|t| h[:to] >= t[2]}
         end
       end
    end
    if joken.keys.include? :toshinbi
       selected = selected.select{|t| t[3].include?(joken[:toshinbi])}
    end
    if joken.keys.include? :kikan
       selected = selected.select{|t| t[4].include?(joken[:kikan])}
    end
    if joken.keys.include? :kikanQuery
       joken[:kikanQuery].each do |k|
         selected = selected.select{|t| t[4].include?(k)}
       end
    end
    if joken.keys.include? :bukai
       selected = selected.select{|t| t[5].include?(joken[:bukai])}
    end
    if joken.keys.include? :bukaiQuery
       ary = []
       selected_ary = joken[:bukaiQuery].map{|bukai| selected.select{|t| t[5].include? bukai}}
       selected_ary.each do |selected|
         ary =  ary | selected
       end
       selected = ary
    end
    if joken.keys.include? :iinQuery
       ary = []
       selected_ary = joken[:iinQuery].map{|iin| selected.select{|t| t[6].include? iin}}
       selected_ary.each do |selected|
         ary =  ary | selected
       end
       selected = ary
    end
    if joken.keys.include? :jorei
       selected = selected.select{|t| t[7].include?(joken[:jorei])}
    end
    if joken.keys.include? :seikyu and joken[:seikyu] != "開示請求訂正請求利用停止請求"
       selected = selected.select{|t| t[8]!="" and joken[:seikyu].include?(t[8])}
    end
    selected
  end
  def get_url(joken)
  	search(joken).map{|i| i[-1]}
  end
  def get_bango(joken="")
    if joken == ""
      @ary.map{|i| i[1]}
    else
      search(joken).map{|i| i[1]}
    end
  end
  def get_toshinbi(bango)
    @ary.find{|data| data[1]==bango}[3]
  end
  def get_jisshikikan(bango)
    @ary.find{|data| data[1]==bango}[4]
  end
  def get_bukai(bango)
    @ary.find{|data| data[1]==bango}[5]
  end
  def get_file_name(bango)
    @ary.find{|data| data[1]==bango}[-3]
  end
  def get_kenmei(bango)
    @ary.find{|data| data[1]==bango}[-2]
  end
  def get_url(bango)
    @ary.find{|data| data[1]==bango}[-1]
  end
  def get_hinagata_data(joken)
    h = Hash.new
    search(joken).each do |i|
      h[i[1]] = {:toshinbi=>i[3],:jisshikikan=>i[4],:bukai=>i[5],:kenmei=>i[-2],:url=>i[-1]}
    end
    if joken.keys.include? :freeWord
      h2 = freeWord_search(joken)
      h2.keys.each do |bango|
        h2[bango][:toshinbi]=h[bango][:toshinbi]
        h2[bango][:jisshikikan]=h[bango][:jisshikikan]
        h2[bango][:bukai]=h[bango][:bukai]
        h2[bango][:kenmei]=h[bango][:kenmei]
        h2[bango][:url]=h[bango][:url]
      end
      return h2
    end
    h
  end
  def freeWord_search(joken)
    def text_range(joken)
      case joken[:freeWordRange]
      when ""             ;  nil
      when "ketsuron"     ;  "審査会の結論.*?(申立て|審査請求|申出)の趣旨"
      when "jisshikikan"  ;  "理由説明要旨.*?((本件処分|決定|回答)等?に対する|申\立人の|審査請求人の)意見"
      when "seikyunin"    ;  "((本件処分|決定|回答)等?に対する|申\立人の|審査請求人の)意見.*?審査会の判断"
      when "shinsakai"    ;  '審査会の判断.*'
      when "shinsakailast";  '(結( |　)+論|[）)]( |　)*結論|[0-9０-９]( |　)+結論)(.*?(^( |　)*別表|別表[0-9０-９]*( |　)*$|別( |　)+表|審査会の経過)|.*)'
      else  nil
      end
    end
    def reg_pattern(word_ary)
      # 検索語が複数の時は、"[^\n]*(検索語1|検索語2|検索語3).*(検索語1|検索語2|検索語3).*?\n"
      # という正規表現をつくる。  
      if word_ary.size > 1 
        "[^\n]{0,100}(#{word_ary.join("|")})(.*(#{word_ary.join("|")}))?[^\n]{0,100}\n?"
      # 検索語が一つの時は、"[^\n]*検索語(.*検索語.*?\n|.*?\n)" という正規表現をつくる。
      else
        "[^\n]{0,100}#{word_ary[0].to_s}(.*#{word_ary[0].to_s})?[^\n]{0,100}\n?"
      end
    end
    def exec_search(str,word_ary,type,range_joken)
      if range_joken and ans = str.match(/#{range_joken}/m)
        str = ans[0]
        p str
      end
      case type
      when "and"
        #マッチしない語句が一つでもあればそのファイルは終了
        word_ary.each do |k|
          return nil unless str.match(/#{k}/)
        end
      when "or"
        #マッチする語句が一つもなければそのファイルは終了
        res = nil
        word_ary.each do |k|
          res = true if str.match(/#{k}/)
        end
        return nil unless res
      end
      #要求された語句を含むことを確認できたらパターンマッチしてマッチした部分を返す
      begin
      str.match(/#{reg_pattern(word_ary)}/m)[0]
      rescue
        #p reg_pattern(word_ary)
        #p str
      end
    end
    h2 = Hash.new
    word_ary,type,range_joken = joken[:freeWord],joken[:freeWordType],text_range(joken)
    get_bango(joken).each do |bango|
      str = File.read(get_file_name(bango)).encode("UTF-8", :invalid => :replace)
      matched_range = exec_search(str,word_ary,type,range_joken)
      if matched_range
        matched_range = matched_range[-800,800] if matched_range.size>800
        #p bango
        #p matched_range
        h2[bango] = {:matched_range => matched_range} 
      end
    end
    h2
  end
end

#toshin=Toshin.new
# toshin.get_bango({:num => {:from => "1500",:to => "1700"},:iin=>"藤原"})
#h=toshin.get_hinagata_data({:num => {:from => "150",:to => "2500"}})
#p h
#p h["答申第1442号から第1444号まで"]

