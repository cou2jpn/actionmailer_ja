# -*- coding: utf-8 -*-
require 'nkf'
require 'action_mailer/version'

# = ActionMailer::Ja
# 
# Ruby on Rails 2.x に対応。
module ActionMailer
  module Ja
    # @auto_base64_encode is *obsoleted*
    # Subject, From, Recipients, Cc を自動的に base64 encode するかの真偽値。（デフォルト true）
    #
    # Examples:
    #  ActionMailer::Ja.auto_base64_encode = false
    #
    @@auto_base64_encode = true
    mattr_accessor :auto_base64_encode

    # 機種依存文字を安全な文字に置換するかの真偽値。（デフォルト false）
    #
    # Examples:
    #  ActionMailer::Ja.auto_replace_safe_char = true
    #
    @@auto_replace_safe_char = false
    mattr_accessor :auto_replace_safe_char

    # Mobile Layout
    attr_accessor :mobile_layout

    def self.included(base) #:nodoc:
      base.class_eval do
        alias_method_chain :render_message, :jpmobile
        alias_method_chain :render, :ja
        alias_method_chain :create_mail, :ja
        alias_method_chain :quote_if_necessary, :ja
        self.default_charset = 'iso-2022-jp' unless defined? Locale
      end
    end

    def quote_if_necessary_with_ja(text, charset)
      text = replace_safe_char(text) if auto_replace_safe_char
      if mobile_address? && @mobile_address.softbank?
        charset = 'utf-8'
      elsif charset == 'iso-2022-jp'
        text = NKF.nkf('-jW -m0 --oc=CP50220', text).strip
      end
      return quote_if_necessary_without_ja(text, charset)
    end

    # Locale があるかどうかで GetText が読み込まれたかを判断する
    def gettext?
      return defined? Locale
    end

    def create_mail_with_ja #:nodoc:
      create_mail_without_ja
      (@mail.parts.empty? ? [@mail] : @mail.parts).each { |part|
        if part.content_type == 'text/plain' || part.content_type == 'text/html'
          encode_parts(part)
        elsif part.content_type == 'multipart/alternative'
          part.parts.each { |part|
            encode_parts(part)
          }
        end
      }
      @mail
    end

    def encode_parts(part)
      if ((!gettext?) || (gettext? && Locale.get.language == "ja"))
        if mobile_address? && @mobile_address.softbank?
          part.charset = 'utf-8'
          part.body = NKF.nkf('-w', part.body)
          part.transfer_encoding = '8bit'
        else
          part.charset = 'iso-2022-jp'
          part.body = NKF.nkf('-j --oc=CP50220', part.body)
          part.transfer_encoding = '7bit'
        end
      end
    end

    # 携帯メールアドレスの場合、view テンプレートを変更します。
    # まず携帯キャリア別のテンプレートを探し存在すればそれを利用します。（拡張子は erb である必要はありません） 
    #
    #  xx_mobile_docomo.erb 
    #  xx_mobile_au.erb 
    #  xx_mobile_softbank.erb 
    #  xx_mobile_willcom.erb 
    #  xx_mobile_iphone.erb 
    #
    # 携帯キャリア別のテンプレートがない場合、携帯共通のテンプレートを探し存在すればそれを利用します。 
    #
    #  xx_mobile.erb 
    #
    # 携帯メール用テンプレートが存在しなければ、通常通りのテンプレートを利用します。 
    #
    #  xx.erb 
    #
    def render_message_with_jpmobile(method_name, body)
      if mobile_address?
        vals = []
        if Array === @mobile_address.career_template_path
          @mobile_address.career_template_path.each do |tp|
            vals << "mobile_#{tp}"
          end
        else
          vals << "mobile_#{@mobile_address.career_template_path}"
        end
        vals << "mobile"

        # 2.2 以降は layout を考慮する。
        if ::ActionMailer::VERSION::MAJOR >=2 && ::ActionMailer::VERSION::MINOR >=2
          if layout_path = active_layout
            paths = layout_path.to_s.split(File::SEPARATOR)
            file_name = File.basename(paths.pop).split(".").first
            layout_dir = paths.join(File::SEPARATOR)
            vals.each do |v|
              mobile_layout_path = "#{file_name}_#{v}"
              template_path = "#{template_root}/#{layout_dir}/#{mobile_layout_path}"
              template_exists ||= Dir.glob("#{template_path}.*").any? { |i| File.basename(i).split(".").length > 0 }
              if template_exists
                layout_path = mobile_layout_path
                break;
              end
            end
          end
          self.mobile_layout = layout_path.to_s
        end
        file_name = File.basename(method_name.to_s).split(".")[0]
        vals.each do |v|
          mobile_path = "#{file_name}_#{v}"
          template_path = "#{template_root}/#{mailer_name}/#{mobile_path}"
          template_exists ||= Dir.glob("#{template_path}.*").any? { |i| File.basename(i).split(".").length > 0 }
          return render_message_without_jpmobile(mobile_path, body) if template_exists
        end
      end
      render_message_without_jpmobile(method_name, body)
    end

    def render_with_ja(opts)
      if ::ActionMailer::VERSION::MAJOR >= 2 && ::ActionMailer::VERSION::MINOR >= 2
        opts.merge!(:layout => self.mobile_layout) if mobile_address? && !self.mobile_layout.nil?
        render_without_ja(opts)
      else
        render_without_ja(opts)
      end
    end

    # 機種依存文字を安全な文字に置換します。
    def replace_safe_char(src=nil)
      return nil if src.nil?
      return src.split(//).map {|c| (s = REPLACE_CHAR_MAP[c]).nil? ? c : s }.join
    end

    protected

    def mobile_address?
      if @mobile_address.nil?
        @mobile_address = self.mobile_address
        @mobile_address = false if @mobile_address.nil?
      end
      return @mobile_address
    end

    # 携帯メールアドレスオブジェクトを取得します。
    # 携帯メールアドレスでない場合、 nil が返されます。
    # recipients が複数指定されている場合、最初のメールアドレスで判断します。
    def mobile_address
      recipient = recipients.is_a?(Array) ? recipients[0] : recipients
      email_addr = parse_mail_addr(recipient)
      ActionMailer::JpMobile.constants.each do |const|
        c = ActionMailer::JpMobile.const_get(const)
        next if c.is_a?(Hash)
        if c::MAIL_ADDR_REGEXP =~ email_addr
          @mobile_address = c.new
          return @mobile_address
        end
      end
      @mobile_address = false
      return nil
    end

    # recipient からメールアドレスを取り出します。
    def parse_mail_addr(recipient)
      /(.*?)<(.*?)>/ =~ recipient
      return $& ? $2 : recipient
    end

  end
end
