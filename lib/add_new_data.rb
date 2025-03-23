require 'kconv'
require 'json'
require "net/https"
require 'open-uri'
begin
  require 'poppler'
rescue LoadError
  require 'pdf-reader'
end
require_relative 'send_nifty_mail'
require_relative 's3_client'

module DataProcessor
  extend self
  ROOT_DIR = File.expand_path('..', __dir__)
  TMP_DIR = File.join(ROOT_DIR, 'tmp')
  URL = "https://www.city.yokohama.lg.jp/city-info/gyosei-kansa/joho/kokai/johokokaishinsakai/shinsakai/"
  Dest = "#{TMP_DIR}/temp.pdf"
  
  #保存済みの最新答申番号後の答申番号,URL,件名を取得する。
  def get_bango_url_kenmei_after(max_num = nil)
    uri = URI.parse(URL)
    url_list = uri.read.scan(/href="(.*?\.html)">.*?審査会答申一覧/).flatten
    host = uri.host
    toshin_url = {}
    toshin_kenmei = {}
    #配列の最初が最新の年度。最初の2年分調べれば十分だろう。
    if max_num
      n = 2
    else
      n = -1
    end
    url_list[0,n].each do |url|
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
          if max_num==nil or max_num < num.to_i
            toshin_url[num] = u_b[0]
            toshin_kenmei[num] = kenmei
          end
        end
      end
    end
    return nil if toshin_url.size==0
    [toshin_url,toshin_kenmei]
  end
  
  def get_text_from(url,s3)
    uri  = URI.parse(url)
    open(Dest, "w+b") do |dest|
      dest.write(uri.read)
    end
    begin
      document = Poppler::Document.new(Dest)
    rescue NameError
      document = PDF::Reader.new(Dest)
    end
    str = ""
    num = ""
    toshin_num = ""
    document.pages.each_with_index do |page,i|
      begin
        s = page.get_text
      rescue NoMethodError
        s = page.text
      end
      if i == 0
        toshin_num = s.tr("０-９","0-9").match(/答申第\d+号((から|及び)第\d+号(まで)?)?/)[0]
      end
      str += s.sub(/\s+－[0-9０-９]{1,2}－$/,"\n")
    end
    unless str == ""
      str = str.toutf8.gsub(" ","").tr("０-９","0-9").gsub(/−\d\d?−/,"").gsub(/^\s*\n+/m,"").
                sub("紙申審査会","審査会").
                gsub(/(?<!審査会の結論|審査請求の趣旨|説明要旨|本件処分に対する意見|審査会の判断|結論)\s*\n\s*(?!\s*([１-５ア-ンa-z]\s|\([1-9ｱ-ﾄa-z]\)|（第.部会）|（制度運用調査部会）|別表))/m,"")
      file_name = "#{toshin_num}.txt"
      [file_name,str]
    else
      nil
    end
  end
  def get_num_array_from(bango)
    puts bango
    p bango
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
  def get_midashi_data_from(text_file,s3)
    #str = File.read(text_file).encode("UTF-8", :invalid => :replace).gsub(/\s|　/,"").tr("０-９","0-9")
    str = s3.read(text_file).encode("UTF-8", :invalid => :replace).gsub(/\s|　/,"").tr("０-９","0-9")
    begin
      if ans1 = str.match(/.*様(?=横浜市情報公開・個人情報保護審査会会長|横浜市公文書公開審査会会長)/)
        #item = ans1[0].scan(/[\(（](答申第[\d-]+号.*?)[）\)].*([平成|令和]元?\d?\d?年\d\d?月\d\d?日).*?\d日(.*)様/).flatten
        #bango,yyyymmdd,toshinbi,jisshikikan = item[0],item[1].to_yyyymmdd,item[1],item[2]
        item = ans1[0].scan(/[\(（](答申第[\d-]+号.*?)[）\)].*((平成|令和)(元|\d+)年\d{1,2}月\d{1,2}日).*?\d日(.*)様/).flatten  
        bango,yyyymmdd,toshinbi,jisshikikan = item[0],item[1].to_yyyymmdd,item[1],item[4]      
        jisshikikan = jisshikikan.gsub(/市長|議長|水道事業管理者|病院事業管理者|交通事業管理者|選挙管理委員会委員長|人事委員会委員長|監査委員|農業委員会会長|固定資産評価審査委員会委員長|理事長|消防長/,'\0 ').gsub(/様/,', ') 
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
    rescue => e
      err = [e.message] << e.backtrace 
      err_str = err.join("\n")
      puts err_str
      send_mail(err_str)
    end
    #[ bango,yyyymmdd,toshinbi,jisshikikan,bukai,iin,jorei,seikyu ]
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
  end
  def time_stamp()
    File.write("#{TMP_DIR}/search_new_pdf.txt",Time.now)
  end
  
  def self.add_new_data(logger,toshin)
    begin
      # ************* ログ出力 ********************
      logger.info "Loop task start at #{Time.now}"
      # ******************************************
      
      s3 = S3Client.new
      #midashi = JSON.parse(File.read("#{TMP_DIR}/bango_hizuke_kikan.json"))
      #midashi = JSON.parse(s3.read("bango_hizuke_kikan.json"))
      midashi = toshin.midashi.dup
      p midashi
      #保存済みの最新答申番号
      saved_max_num = midashi.map{|data| data[:num_array][0].to_i}.max
      logger.info "saved_max_num => " + saved_max_num.to_s
      toshin_url, toshin_kenmei = get_bango_url_kenmei_after(saved_max_num)
      if toshin_url==nil
        logger.info "新しい答申はありませんでした。"
        time_stamp
        return nil
      end
      puts "add_new_data"
      puts toshin_url
      puts toshin_kenmei
      file_name_array=[]
      toshin_url.keys.each do |num|
        puts "num => " + num.to_s
        #Pdfから答申番号と答申本文のテキストを抽出
        file_name, toshin_text = get_text_from(URL+toshin_url[num], s3)
        #答申のテキストを答申番号のファイル名で保存
        s3.write(file_name, toshin_text)
        File.write(TMP_DIR+"/"+file_name, toshin_text)
        file_name_array << file_name

        puts "Got text data form pdf : " + file_name
        #答申のテキストデータから見出し情報を抽出し、見出配列に追加するハッシュデータを作成
        h = get_midashi_data_from(file_name, s3)
        puts "Got midashi data" 
        puts h
        puts 'h[:bango] => ' + h[:bango].to_s
        h[:num_array] = get_num_array_from(h[:bango])
        h[:file_name] = file_name
        h[:url]       = toshin_url[num]
        h[:kenmei]    = toshin_kenmei[num]
        p h
        midashi << h
      end
    
      midashi = midashi.sort_by{|h| h[:num_array][0].to_i}
      #File.write("#{TMP_DIR}/bango_hizuke_kikan.json",JSON.generate(midashi))
      json = JSON.generate(midashi)
      s3.write("bango_hizuke_kikan.json", json)
      File.write("#{TMP_DIR}/bango_hizuke_kikan.json", json)
      time_stamp
    rescue => e
      err = [e.message] << e.backtrace 
      err_str = err.join("\n")
      logger.error 'failed add_new_data'
      logger.error err_str
      send_mail(err_str)
    end
    # ************* ログ出力 ********************
    logger.info  "Task ended at #{Time.now}"
    # ******************************************
    return file_name_array
  end
end

##********** 実行テスト ************
#require_relative 'kensaku_with_ripgrep_via_Open3_and_precut'
#Encoding.default_external = "utf-8"
#logger=Logger.new(STDOUT)
#toshin=Toshin.new
#puts DataProcessor.add_new_data(logger,toshin)