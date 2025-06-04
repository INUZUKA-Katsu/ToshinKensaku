require 'aws-sdk-s3'
require 'kconv'
require 'concurrent'

class S3Client
  attr_reader :bucket
  ROOT_DIR = File.expand_path('..', __dir__)
  TMP_DIR = File.join(ROOT_DIR, 'tmp')
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
      res << obj.key
    end
    res
  end
  # 起動時にtmpフォルダを確認し、不足するファイルをダウンロードする。
  def fill_tmp_folder
    s3_files = get_list.map{|f| f.sub("toshin/","")}
    tmp_files = Dir.glob(TMP_DIR+'/*.txt').map{|f| f.sub(/.*tmp\//,"")}
    # スレッド数を64に制限したプールを作成
    pool = Concurrent::ThreadPoolExecutor.new(max_threads: 64)
    (s3_files-tmp_files).each do |f|
      pool.post do
        File.write(TMP_DIR+"/"+f, read(f))
        sleep 0.01
      end
    end
    # プールが終了するのを待つ
    pool.shutdown
    pool.wait_for_termination
  end
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
