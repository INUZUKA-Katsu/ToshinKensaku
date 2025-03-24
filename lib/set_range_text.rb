require 'json'
require 'concurrent'

Encoding.default_external = "utf-8"

class FileProcessingError < StandardError; end

module SetRange
  extend self
  ROOT_DIR = File.expand_path('..', __dir__)
  TMP_DIR = File.join(ROOT_DIR, 'tmp')

  def text_range(joken)
    honbun_end = '(.*?(委員.{3,10}){3}|.*?《参考》|.*?^( |　)*別表|.*?別表[0-9０-９]*( |　)*$|.*?別( |　)+表|.*?審査会の経過|.*)'
    case joken
    when ""             ;  nil
    when "ketsuron"     ;  "審査会の結論.*?(?=((異議)?申立て|審査請求|申出)の趣旨)"
    when "jisshikikan"  ;  "(理由|に関する)説明要旨.*?(?=((処分|決定|回答)等?に対する|申\立人の|審査請求人の)意見)"
    when "seikyunin"    ;  "((処分|決定|回答)等?に対する|申\立人の|審査請求人の)意見.*?(?=審査会の判断)"
    when "shinsakai"    ;  "審査会の判断.*?" + honbun_end
    when "shinsakailast";  '(結( |　)+論|[）)]( |　)*結論|[0-9０-９]( |　)*結論|(?<!審査会の)結( |　)*論\n).*?' + honbun_end
    else  nil
    end
  end
  
  def set_range_text(input_path,pattern)
    #p :set_range_text
    begin
      content = self.safe_read(input_path)
      extracted = self.extract_text(content, pattern, input_path)
      extracted
    rescue FileProcessingError => e
      puts "Error: #{e.message}"
    end
  end
  
  def set_each_range_text(file_name_array=nil)
    p "start set_each_range_text"
    if file_name_array
      path_array = file_name_array.map{|f| TMP_DIR+"/"+f}
    else
      path_array = Dir.glob("#{TMP_DIR}/*.txt").select{|f| f.encode("UTF-8","UTF-8-MAC").match(/号(まで)?\.txt/)}
    end
    joken_array = ["ketsuron","jisshikikan","seikyunin","shinsakai","shinsakailast"]
    pool = Concurrent::ThreadPoolExecutor.new(max_threads: 16)
    output_array = Concurrent::Array.new
    joken_array.each do |joken|
      p joken
      pattern = /#{self.text_range(joken)}/m
      path_array.each do |path|
        pool.post do 
          output_path = path.sub(/\.txt/, joken + ".txt")
          unless File.exist? output_path
            extracted = self.set_range_text(path,pattern)
            self.safe_write(output_path, extracted)
            output_array << output_path
          end
        end
      end
    end
    pool.shutdown
    pool.wait_for_termination
    p "ectracted text: #{output_array.size} saved ex. #{output_array[0]}"
    p "end of pool"
  end

  #tmpフォルダのファイルに不足がないかチェックする
  def file_check(midashi,for_enduser=nil)
    puts for_enduser
    joken_array = ["","ketsuron","jisshikikan","seikyunin","shinsakai","shinsakailast"]
    file_list = midashi.map{|h| h[:file_name]}.
                        map do |f|
                          a=[]
                          joken_array.each do |j|
                            a << f&.sub(/\.txt/, j + ".txt")
                          end
                          a
                       end.flatten
    actual_files = Dir.glob(TMP_DIR+"/答申*").map{|path| File.basename(path)}
    missing_files = file_list - actual_files
    if for_enduser and for_enduser=="用語検索"
      #範囲検索用のファイルを除外
      missing_files.delete_if{|f| f.match(/[a-z]+\.txt/)}
      missing_files
    elsif for_enduser and for_enduser=="詳細用語検索"
      #範囲検索用のファイルを抽出
      missing_files.select!{|f| f.match(/[a-z]+\.txt/)}
      #答申番号に変換
      missing_files = missing_files.map{|f| f.sub(/[a-z\.]+$/,"")}.uniq
      missing_files
    else
      [missing_files, actual_files]
    end
  end
  #tmpフォルダのファイルに不足がないかチェックする
  def file_check_to_html(midashi)
    missing_files, actual_files = file_check(midashi)
    num_of_files = "actual_file: tmpフォルダには #{actual_files.size} の答申テキストファイルがあります。"
    if missing_files.size > 0
      "#{header}#{num_of_files}<br>以下のファイルはtmpフォルダに存在しません。<br>#{missing_files.join('<br>')}#{footer}"
    else
      "#{header}#{num_of_files}<br>所要のファイルはすべてtmpフォルダに存在します。#{footer}"
    end
  end
  def header
    '<!DOCTYPE html><html lang="ja"><head><meta charset="UTF-8"></head><body>'
  end
  def footer
    '</body></html>'
  end
  def safe_read(path, retries: 5, wait: 0.1)
    attempts = 0  
    begin
      return File.read(path)
    rescue Errno::EACCES, Errno::EBUSY, Errno::ENOENT => e
    #Errno::EACCES（アクセス権限エラー）, Errno::EBUSY（ファイルが使用中）, Errno::ENOENT（ファイルが存在しない）
      attempts += 1
      if attempts <= retries
        sleep wait
        retry
      else
        raise FileProcessingError, "File read failed after #{retries} attempts: #{e.message}"
      end
    end
  end
  def extract_text(content, regex, input_path)
    match = content.match(regex)
    if match
      match[0]  # マッチした部分を返す
    else
      raise FileProcessingError, "Pattern not found in content of #{File.basename(input_path)}"
    end
  end
  def safe_write(path, content, retries: 5, wait: 0.1)
    attempts = 0
    begin
      File.write(path, content)
    rescue Errno::EACCES, Errno::EBUSY => e
    # Errno::EACCES（アクセス権限エラー）, Errno::EBUSY（ファイルが使用中）
      attempts += 1
      if attempts <= retries
        sleep wait
        retry
      else
        raise FileProcessingError, "File write failed: #{e.message}"
      end
    end
  end
end
