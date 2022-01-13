require 'mechanize'
require 'kconv'

Net::HTTP.prepend Module.new {
  def use_ssl=(flag)
    super
    self.ciphers = "DEFAULT:!DH"
  end
}
TR=<<EOS
            <td class="search-result-body-left" width="200px">該当部分<br></td>
            <td class="search-result-body-right" width="700px"><--該当部分--><br></td>
EOS

def get_soumu_search_result(search_word)
  
  url='https://koukai-hogo-db.soumu.go.jp/'
  
  agent = Mechanize.new
  agent.user_agent_alias = 'Mac Safari'
  
  page = agent.get(url+"report/")

  form = page.forms[0]
  
  form.checkbox_with(name: 'gyouseiKoukai').check
  form.checkbox_with(name: 'gyouseiHogo'  ).check
  form.checkbox_with(name: 'dokuhouKoukai').check
  form.checkbox_with(name: 'dokuhouHogo'  ).check
  form.checkbox_with(name: 'kaijiSeikyu'  ).check
  form.checkbox_with(name: 'teiseiSeikyu' ).check
  form.checkbox_with(name: 'teishiSeikyu' ).check
  form.field_with(   name: 'limitOption'  ).value = '3'
  form.field_with(   name: 'searchQuery'  ).value = search_word
  
  res = agent.submit(form).body.toutf8

  #File.write("tmp/tmp.html",res)

  if res.match(/検索条件に合致する答申が見つかりませんでした。/)
    res_array = ["検索条件に合致する答申が見つかりませんでした。"]
  else
    res_array = res.gsub(/\/(reportBody)/,url+'\1').
                    gsub(/\/reportPointOutline/,url+'\&').
                    scan(/<table class\="search\-result".*?table>/m)
    #res_array.map! do |table|
    #  honbun_url = table.match(/a href="(http.*?reportBody.*?)"/)[1]
    #  #bango      = table.match(/答申\s第\s[0-9０-９]+号/)[0]
    #  str        = agent.get(honbun_url).body.toutf8.gsub(/<.*?>/m,"")
    #  part_str   = str.scan(/[^\n]{0,200}#{word_array.join("|")}[^\n]{0,200}\n?/).
    #                 map do |s|
    #                   s.gsub!(/#{word_array.join("|")}/,'<strong>\&</strong>')
    #                   s.chomp
    #                 end.
    #                 join("<br><br>")
    #  table.sub(/\n\s+<\/table>/, TR.sub(/<--該当部分-->/,part_str) + '\&')
    #end
  end
  res_array
end

def get_text_range(url,search_word)
  p "search_word => "+search_word
  word_array = search_word.split(/[\s　]+/)
  agent = Mechanize.new
  agent.user_agent_alias = 'Mac Safari'
  str = agent.get(url).body.toutf8.gsub(/<.*?>/m,"")
  part_str   = str.scan(/[^\n]{0,200}#{word_array.join("|")}[^\n]{0,200}\n?/).
                 map do |s|
                   s.gsub!(/#{word_array.join("|")}/,'<strong>\&</strong>')
                   s.chomp
                 end.
                 join("<br><br>")
  TR.sub(/<--該当部分-->/,part_str)
end
