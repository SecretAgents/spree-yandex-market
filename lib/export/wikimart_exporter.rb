# encoding: utf-8
module Export
  class WikimartExporter < YandexMarketExporter

    def initialize
      @utms = '?utm_source=wikimart&utm_medium=yml&utm_campaign=yml'
    end

    protected

    def offer_vendor_model(xml, product)
      variants = product.variants.select { |v| v.count_on_hand > 0 && v.price > 500 }
      count = variants.length
      images = product.images.limit(10)

      gender = case product.gender
                 when 1 then 'Мужской'
                 when 2 then 'Женский'
                 else ''
               end

      variants.each do |variant|
        opt = { :type => 'vendor.model', :available => true }

        opt[:id] = count > 1 ? variant.id : product.id
        opt[:group_id] = product.id if count > 1

        model = model_name(product)

        xml.offer(opt) do
          xml.url "http://#{@host}/id/#{product.id}#{@utms}"
          xml.price variant.price
          xml.currencyId currency_id
          xml.categoryId product_category_id(product)
          xml.market_category market_category(product)
          images.each do |image|
            xml.picture image_url(image)
          end
          xml.delivery true
          xml.vendor product.brand.name if product.brand
          if add_alt_vendor? && product.brand && product.brand.alt_displayed_name.present?
            xml.vendorAlt product.brand.alt_displayed_name
          end
          xml.vendorCode product.sku
          xml.model model
          xml.description product_description(product) if product_description(product)
          xml.country_of_origin product.country.name if product.country
          size = variant_size(variant)
          xml.param size.presentation, name: 'Размер', type: 'size', unit: 'RU' if size
          xml.param product.colour, name: 'Цвет', type: 'colour'
          xml.param gender, :name => 'Пол' if gender.present?
          xml.param product.localized_age, :name => 'Возраст' if product.age
          xml.param product.picture_type, :name => 'Тип рисунка' if product.picture_type
          additional_params_for_offer(xml, product)
        end
      end
    end

    def variant_size(variant)
      variant.option_values.
        find{ |ov| ov && ov.option_type.presentation == 'Размер' && ov.presentation != 'Без размера' }
    end

  end
end