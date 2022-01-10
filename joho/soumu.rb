require 'mechanize'

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
  
  if res.match(/検索条件に合致する答申が見つかりませんでした。/)
    res_array = ["検索条件に合致する答申が見つかりませんでした。"]
  else
    res_array = res.gsub(/\/reportBody/,url+'\&').
                    gsub(/\/reportPointOutline/,url+'\&').
                    scan(/<table class\="search\-result".*?table>/m)
  end
  res_array
end