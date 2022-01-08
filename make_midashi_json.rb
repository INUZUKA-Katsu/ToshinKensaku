require 'json'
require 'kconv'
require "net/https"
require 'open-uri'
require 'pdf-reader'

URL = "https://www.city.yokohama.lg.jp/city-info/gyosei-kansa/joho/kokai/johokokaishinsakai/shinsakai/"


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
class Hash
  def key_to_s()
    new_h = Hash.new
    self.keys.each do |k|
      new_h[k.to_s]=self[k]
    end
    new_h
  end
  def key_to_sym()
    new_h = Hash.new
    self.keys.each do |k|
      new_h[k.to_sym]=self[k]
    end
    new_h
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
def get_bango_url_kenmei
  uri = URI.parse(URL)
  url_list = uri.read.scan(/href="(.*?\.html)">.*?審査会答申一覧/).flatten
  host = uri.host
  
  toshin_url = {}
  toshin_kenmei = {}
  
  url_list.each do |url|
    uri =  URI.parse("https://"+host+url)
    url_bango_kenmei_array = uri.read.scan(/<li>(<a.*?)<br>(.*?)<\/li>/i)
    url_bango_kenmei_array.each do |url_bango_kenmei|
      url_bango = url_bango_kenmei[0]
      kenmei    = url_bango_kenmei[1]
      url_bango.scan(/<a href="(.*?pdf)".*?(答申第.*?号(?!から)(まで)?)/).each do |u_b|
        if ans = u_b[1].tr("０-９","0-9").match(/\d+/)
          num = ans[0]
        else
          p "u_b[1] => "+u_b[1].to_s
        end
        toshin_url[num] = u_b[0]
        toshin_kenmei[num] = kenmei
      end
    end
  end
  [toshin_url,toshin_kenmei]
end
def get_num_array_from(bango)
   if bango.match(/から/)
     res = bango.match(/(\d+)号から.*?(\d+)/)
     n = []
     (res[1].to_i..res[2].to_i).each do |num|
       n << num.to_s 
     end
     return n
   elsif bango.match(/及び/)
     res = bango.match(/(\d+)号及び.*?(\d+)/)
     return [ res[1], res[2] ]
   else
     res = bango.match(/\d+/)
     return [ res[0] ]
   end
end
def get_midashi_data_from(text_file)
  str = File.read(text_file).encode("UTF-8", :invalid => :replace).gsub(/\s|　/,"").tr("０-９","0-9")
  begin
    if ans1 = str.match(/.*様(?=横浜市情報公開・個人情報保護審査会会長|横浜市公文書公開審査会会長)/)
      item = ans1[0].scan(/[\(（](答申第[\d-]+号.*?)[）\)](..元?\d?\d?年\d\d?月\d\d?日).*?\d日(.*)様/).flatten
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
  h = Hash.new
  h[:bango]=bango
  h[:yyyymmdd]=yyyymmdd
  h[:toshinbi]=toshinbi
  h[:jisshikikan]=jisshikikan
  h[:bukai]=bukai
  h[:iin]=iin
  h[:jorei]=jorei
  h[:seikyu]=seikyu
  h
  #[ bango,yyyymmdd,toshinbi,jisshikikan,bukai,iin,jorei,seikyu ]
end
def make_midashi_json
  num2url, num2kenmei = get_bango_url_kenmei
  ary=[]
  Dir.glob("tmp/答申*txt").each do |f|
    #bango,yyyymmdd,toshinbi,jisshikikan,bukai,iin,jorei,seikyu = get_midashi_data_from(f)
    h = get_midashi_data_from(f)
    h[:num_array] = get_num_array_from(h[:bango])
    h[:file_name] = f
    num           = h[:num_array][0]
    h[:url]       = num2url[num]
    h[:kenmei]    = num2kenmei[num]
    ary << h
    #ary << [ num_array,bango,yyyymmdd,toshinbi,jisshikikan,bukai,iin,jorei,seikyu,f,num2kenmei[num],num2url[num] ]
  end
  ary = ary.sort_by{|h| h[:num_array][0].to_i}.map{|h| h.key_to_s}
  File.write("tmp/bango_hizuke_kikan.json",JSON.generate(ary))
  FileUtils.cp("tmp/bango_hizuke_kikan.json","text/bango_hizuke_kikan.json") #Heroku上では無効
  return ary
end
make_midashi_json
