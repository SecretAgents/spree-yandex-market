# encoding: utf-8

require 'nokogiri'

module Export
  class YandexMarketExporter
    include Rails.application.routes.url_helpers
    include ActionView::Helpers::SanitizeHelper

    attr_accessor :host, :currencies

    MIN_ORDER_AMOUNT = 500

    def initialize
      @utms = '?utm_source=yandex&utm_medium=market&utm_campaign=market'
    end

    def helper
      @helper ||= ApplicationController.helpers
    end

    def export
      @config = Spree::YandexMarket::Config.instance
      @host = @config.preferred_url.sub(%r[^http://],'').sub(%r[/$], '')

      @currencies = @config.preferred_currency.split(';').map{ |x| x.split(':') }
      @currencies.first[1] = 1

      @preferred_category = preferred_category
      unless @preferred_category.export_to_yandex_market
        raise "Preferred category <#{@preferred_category.name}> not included to export"
      end

      @categories = @preferred_category.descendants.where(:export_to_yandex_market => true)

      @categories_ids = @categories.collect { |x| x.id }

      Nokogiri::XML::Builder.new(:encoding => 'utf-8') do |xml|
        xml.doc.create_internal_subset('yml_catalog', nil, 'shops.dtd')

        xml.yml_catalog({:date => Time.now.to_s(:ym)}.merge(namespaces)) {
          xml.shop { # описание магазина
                     xml.name    @config.preferred_short_name
                     xml.company @config.preferred_full_name
                     xml.url     path_to_url('')

                     xml.currencies { # описание используемых валют в магазине
                                      @currencies && @currencies.each do |curr|
                                        opt = { :id => curr.first, :rate => curr[1] }
                                        opt.merge!({ :plus => curr[2] }) if curr[2] && ["CBRF","NBU","NBK","CB"].include?(curr[1])
                                        xml.currency(opt)
                                      end
                                      }

                     xml.categories { # категории товара
                                      @categories_ids && @categories.each do |cat|
                                        @cat_opt = { :id => cat.id }
                                        @cat_opt.merge!({ :parentId => cat.parent_id }) if cat.level > 1 && cat.parent_id.present?
                                        xml.category(@cat_opt){ xml  << cat.name }
                                      end
                                      }

                     xml.offers { # список товаров
                                  products.each do |product|
                                    offer_vendor_model(xml, product)
                                  end
                                  }
                     }
        }
      end.to_xml
    end

    protected

    def offer_vendor_model(xml, product)
      return unless product.brand.present? # 'vendor' element is required

      variants = product.variants #.select { |v| v.count_on_hand > 0 } need all variants
      count = variants.length
      images = product.images.limit(10)

      gender = case product.gender
      when 1 then 'Мужской'
      when 2 then 'Женский'
      else ''
      end

      variants.each do |variant|
        opt = {type: 'vendor.model', available: variant.available?}

        opt[:id] = variant.id
        opt[:group_id] = product.id if count > 1

        model = model_name(product, variant)

        price = variant.price
        if price.to_i > 1
          xml.offer(opt) do
            xml.url "http://#{@host}/id/#{product.id}#{@utms}"
            xml.price price
            old_price = variant.old_price
            if old_price.to_i > 0 and price / old_price <= 0.95
              xml.oldprice old_price
            end
            xml.currencyId currency_id
            xml.categoryId product_category_id(product)
            xml.market_category market_category(product)
            images.each do |image|
              xml.picture image_url(image)
            end
            xml.delivery true
            xml.vendor product.brand.name
            xml.vendorCode product.sku
            if add_alt_vendor? && product.brand && product.brand.alt_displayed_name.present?
              xml.vendorAlt product.brand.alt_displayed_name
            end
            xml.model model
            xml.description product_description(product) if product_description(product)
            xml.sales_notes "Минимальная сумма заказа - #{MIN_ORDER_AMOUNT} руб."
            xml.country_of_origin product.country.name if product.country
            xml.barcode variant.barcode if variant.barcode.present?
            variant.option_values.each do |ov|
              unless ov.presentation == 'Без размера'
                unit = product.size_table ? product.size_table.standarted_size_table : 'BRAND'
                xml.param ov.presentation, :name => ov.option_type.presentation, :unit => unit
              end
            end
            xml.param product.colour, :name => 'Цвет'
            xml.param gender, :name => 'Пол' if gender.present?
            xml.param product.localized_age, :name => 'Возраст' if product.age
            xml.param product.picture_type, :name => 'Тип рисунка' if product.picture_type
            xml.param series(product), name: 'Линейка' if series(product).present?
            xml.param age_from(variant), name: 'Возраст от', unit: 'месяцев' if age_from(variant).present?
            xml.param age_to(variant), name: 'Возраст до', unit: 'месяцев' if age_to(variant).present?
            xml.param variant.width, name: 'Ширина', unit: 'см' if variant.width.present?
            xml.param variant.height, name: 'Высота', unit: 'см' if variant.height.present?
            xml.param variant.depth, name: 'Глубина', unit: 'см' if variant.depth.present?
            xml.param variant.weight, name: 'Вес', unit: 'кг' if variant.weight.present?
            product.product_properties.each do |product_property|
              xml.param product_property.value, name: product_property.property.name
            end
            if product.orthopedic_properties.present?
              xml.param product.orthopedic_properties.map(&:name).join(', '), name: 'Ортопедические свойства'
            end
            xml.param seasons(product), name: 'Сезоны' if seasons(product).present?
            additional_params_for_offer(xml, product, variant)
          end
        end
      end
    end

    def path_to_url(path)
      "http://#{@host.sub(%r[^http://],'')}/#{path.sub(%r[^/],'')}"
    end

    def image_url(image, wowm = false)
      "#{asset_host(image.to_s)}#{image.attachment.url((wowm == true ? :large_wowm : :large), false)}"
    end

    
    def asset_host(source)
      "http://assets0#{(1 + source.hash % 5).to_s + '.' + @host}"
    end

    def preferred_category
      Taxon.find_by_name(@config.preferred_category)
    end

    def product_category_id(product)
      if product.yandex_market_category
        product.yandex_market_category_id
      else
        product.cat.yandex_market_category_id if product.cat && product.cat.yandex_market_category
      end
    end

    def product_description(product)
      if product.description.present? or product.short_description.present?
        strip_tags(product.short_description.to_s + ' ' + product.description.to_s).strip
      end
    end

    def market_category(product)
      product.market_category if product.market_category.present?
    end

    def add_alt_vendor_to_model_name?;true;end
    def add_alt_vendor?;false;end

    def products
      products = Product.not_gifts.master_price_gte(0.001)
      products.uniq.select do |p|
        p.has_stock? && p.export_to_yandex_market && p.yandex_market_category_including_catalog &&
          p.yandex_market_category_including_catalog.export_to_yandex_market
      end
    end

    def model_name(product, variant)
      model = []
      if add_alt_vendor_to_model_name? && product.brand && product.brand.alt_displayed_name.present?
        model << "(#{product.brand.alt_displayed_name})"
      end
      model << product.name
      if @config.present?
        if @config.preferred_extra_model == "sizes"
          variant.option_values.each do |ov|
            unless ov.presentation == 'Без размера'
              model << "[%s]" % ov.presentation
            end
          end
        else
          model << "(#{I18n.t("for_#{GENDER[product.try(@config.preferred_extra_model)].to_s}")})" if product.try(@config.preferred_extra_model).present?
        end
      end

      model.join(' ')
    end

    def currency_id
      @currencies.first.first
    end

    def series(product)
      series_property = product.product_properties.find{ |p| p.property.name.mb_chars.downcase == 'серия' }
      unless series_property.present?
        series_property = product.product_properties.find{ |p| p.property.name.mb_chars.downcase == 'коллекция' }
      end
      series_property.value if series_property.present?
    end

    def age_from(variant)
      variant.age_from if variant.respond_to?(:age_from) && variant.age_from.present?
    end

    def age_to(variant)
      variant.age_to if variant.respond_to?(:age_to) && variant.age_to.present?
    end

    def seasons(product)
      product.season.map{ |s| I18n.t(s) }.join(', ')
    end

    def additional_params_for_offer(xml, product, variant)
      # nothing
    end

    def namespaces
      {}
    end

  end
end
