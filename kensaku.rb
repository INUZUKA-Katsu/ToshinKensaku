require 'json'
require 'kconv'
require "net/https"
require 'open-uri'
require 'pdf-reader'

class Hash
  def key_to_sym()
    new_h = Hash.new
    self.keys.each do |k|
      new_h[k.to_sym]=self[k]
    end
    new_h
  end
end
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
  elsif param["johoKokai"]==nil and param["kojinjohoHogo"]==nil
    joken[:jorei] = ""
  end
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

class Toshin
  def initialize
    @midashi = JSON.parse(File.read("tmp/bango_hizuke_kikan.json")).map{|h| h.key_to_sym}
  end
  def search(joken) #jokenはハッシュ
    selected = @midashi
    if joken.keys.include? :jorei
       selected = selected.select{|h|
         p "h[:jorei].include?(joken[:jorei]) => " + h[:jorei] + " include? " + joken[:jorei]
         joken[:jorei].include?(h[:jorei])
       }
    end
    if joken.keys.include? :seikyu and joken[:seikyu] != "開示請求訂正請求利用停止請求"
       selected = selected.select{|h|
         p "joken[:seikyu].include?(h[:seikyu]) => " + joken[:seikyu] + " include? " + h[:seikyu]
         h[:seikyu]!="" and joken[:seikyu].include?(h[:seikyu])
       }
    end
    if joken.keys.include? :num
       if joken[:num].class==String
         selected = selected.select{|h| h[:num_array].include?(joken[:num])}
       elsif joken[:num].class==Hash
         j = joken[:num]
         if j.keys.size==2
           a = []
           (j[:from]..j[:to]).each{|n| a<<n}
           selected = selected.select{|h| (h[:num_array] & a).size>0 }
         elsif j.keys[0]==:from
           selected = selected.select{|h| j[:from].to_i <= h[:num_array].max.to_i }
         elsif j.keys[0]==:to
           selected = selected.select{|h| j[:to].to_i >= h[:num_array].min.to_i }
         end
       end
    end
    if joken.keys.include? :bango
       selected = selected.select{|h| h[:bango].include?(joken[:bango])}
    end
    if joken.keys.include? :yyyymmdd
       if joken[:yyyymmdd].class==String
         selected = selected.select{|h| h[:yyyymmdd].include?(joken[:yyyymmdd])}
       elsif joken[:yyyymmdd].class==Hash
         j = joken[:yyyymmdd]
         if j.keys.size==2
           selected = selected.select{|h| (j[:from]..h[:to]).include?(h[:yyyymmdd])}
         elsif j.keys[0]==:from
           selected = selected.select{|h| j[:from] <= h[:yyyymmdd]}
         elsif j.keys[0]==:to
           selected = selected.select{|h| j[:to] >= h[:yyyymmdd]}
         end
       end
    end
    if joken.keys.include? :toshinbi
       selected = selected.select{|h| h[:toshinbi].include?(joken[:toshinbi])}
    end
    if joken.keys.include? :kikan
       selected = selected.select{|h| h[:jisshikikan].include?(joken[:kikan])}
    end
    if joken.keys.include? :kikanQuery
       joken[:kikanQuery].each do |k|
         selected = selected.select{|h| h[:jisshikikan].include?(k)}
       end
    end
    if joken.keys.include? :bukai
       selected = selected.select{|h| h[:bukai].include?(joken[:bukai])}
    end
    if joken.keys.include? :bukaiQuery
       ary = []
       selected_ary = joken[:bukaiQuery].map{|bukai| selected.select{|h| h[:bukai].include? bukai}}
       selected_ary.each do |selected|
         ary =  ary | selected
       end
       selected = ary
    end
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
  def get_hinagata_data(joken)
    if joken.keys.include? :freeWord
      p :step1
      puts File.read("tmp/答申第2199号から第2200号まで.txt")
      selected = freeWord_search(joken)
    else
      selected = search(joken)
    end
    res = Hash.new
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
    res
  end
  def freeWord_search(joken)
    def text_range(joken)
      case joken[:freeWordRange]
      when ""             ;  nil
      when "ketsuron"     ;  "審査会の結論.*?(?=((異議)?申立て|審査請求|申出)の趣旨)"
      when "jisshikikan"  ;  "理由説明要旨.*?(?=((本件処分|決定|回答)等?に対する|申\立人の|審査請求人の)意見)"
      when "seikyunin"    ;  "((本件処分|決定|回答)等?に対する|申\立人の|審査請求人の)意見.*?(?=審査会の判断)"
      when "shinsakai"    ;  '審査会の判断.*'
      when "shinsakailast";  '(結( |　)+論|[）)]( |　)*結論|[0-9０-９]( |　)+結論)(.*?(^( |　)*別表|別表[0-9０-９]*( |　)*$|別( |　)+表|審査会の経過)|.*)'
      else  nil
      end
    end
    def reg_pattern(word_ary)
      # 検索語が複数の時は、"[^\n]*(検索語1|検索語2|検索語3).*(検索語1|検索語2|検索語3).*?\n"
      # という正規表現をつくる。  
        "[^\n]{0,100}(#{word_ary.join("|")})(.*(#{word_ary.join("|")}))?[^\n]{0,100}\n?"
    end
    def exec_search(str,word_ary,type,range_joken)
      if range_joken and ans = str.match(/#{range_joken}/m)
        str = ans[0]
        #p str
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
      p :step4
      begin
      str_range = str.match(/#{reg_pattern(word_ary)}/m)[0]
      #str_range.scan(/[^\n]{0,100}#{word_ary.join("|")}(.*?#{word_ary.join("|")}[^\n]{0,100})?/).
      str_range.scan(/[^\n]{0,200}#{word_ary.join("|")}[^\n]{0,200}\n?/).
                map do |s|
                  s.gsub!(/#{word_ary.join("|")}/,'<strong>\&</strong>')
                  s.chomp
                end.
                join("<br><br>")
      rescue
        #p reg_pattern(word_ary)
        #p str
      end
    end
    word_ary,type,range_joken = joken[:freeWord],joken[:freeWordType],text_range(joken)
    res = Array.new
    selected = search(joken)
    p :step2
    i=0
    selected.each do |h|
      file_name = h[:file_name]
      p file_name
      str = File.read(file_name).encode("UTF-8", :invalid => :replace)
      matched_range = exec_search(str,word_ary,type,range_joken)
      if matched_range
        i+=1
        p i
        h[:matched_range] = matched_range
        res << h
      end
    end
    res
  end
end

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
      str.sub!(/("#{h[k]}")>/, '\1 selected>') if h[k]!=""
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

 