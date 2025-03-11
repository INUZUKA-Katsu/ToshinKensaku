
require 'json'

Encoding.default_external = "utf-8"

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

def 範囲データ作成保存
  puts :start_make_range_text
  err=[]
  path_array = Dir.glob("/Users/inuzuka0601/Sites/Toshin/tmp/*.txt").select{|f| f.encode("UTF-8","UTF-8-MAC").match(/号(まで)?\.txt/)}
  joken_array = ["ketsuron","jisshikikan","seikyunin","shinsakai","shinsakailast"]
  joken_array.each do |joken|
    path_array.each do |path|
        str = File.read(path)  
        if ans=str.match(/#{text_range(joken)}/m)
          str = ans[0].tr("０-９","0-9")
          #puts str[0,500]
          new_path = path.sub(/\.txt/, joken + ".txt")
          #p new_path if new_path.match(/まで/)
          File.write(new_path,str)
          puts new_path
        else
          err << [File.basename(path),joken]  
        end
    end
  end
  err.each do |e|
      p e[0] + " => " + e[1]
  end
end
範囲データ作成保存

def ファイル存在チェック
    res = []
    joken_array = ["ketsuron","jisshikikan","seikyunin","shinsakai","shinsakailast"]
    path = "#{__dir__}/tmp/"
    json = File.read("#{__dir__}/tmp/bango_hizuke_kikan.json")
    midashi = JSON.parse(json)
    midashi.each do |h|
      if File.exist? path + h["file_name"]
        #p "OK " + h["file_name"] 
      else
        p "NO " + h["file_name"] 
      end
      joken_array.each do |joken|
        f = h["file_name"].sub(/号(まで)?\.txt/,'号\1'+joken+'.txt')
        if File.exist? path + f
          #p "OK " + f
        else
          p "NO " + f
          ans = f.match(/\d+/)
          res << ans[0]
        end
      end
    end
    p res.uniq
end
#ファイル存在チェック
