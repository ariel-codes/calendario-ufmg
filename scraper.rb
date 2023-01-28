#!/usr/bin/env ruby
# frozen_string_literal: true

require "rubygems"
require "bundler"
Bundler.setup(:default)

require "open-uri"
require "nokogiri"
require "csv"
require "json"
require "icalendar"

class Scraper
  BASE_URL = "https://ufmg.br/a-universidade/calendario-academico"

  def initialize
    @events = []
  end

  def call(years:)
    years.each do |year|
      1.upto(12) do |month|
        doc = Nokogiri::HTML(URI.open(url(year, month)))
        event_elements = doc.xpath("//a[@data-info-title]")
        event_elements.each do |event_element|
          @events << extract_event_data(event_element)
        end
      end
    end

    @events
  end

  private

  def url(ano, mes)
    "#{BASE_URL}?ano=#{ano}&mes=#{mes}"
  end

  def attribute(element, attribute)
    element.attributes[attribute].value
  end

  def extract_event_data(element)
    description = element.text
    {
      title: description,
      start: DateTime.parse(attribute(element, "data-info-init-date")).to_date,
      end: DateTime.parse(attribute(element, "data-info-end-date")).to_date,
      flags: {
        grad: description.match?(/\bgraduação\b/i),
        pos: description.match?(/\bpós-graduação\b/i),
        matricula: description.match?(/\bmatrícula\b/i),
        trancamento: description.match?(/\btrancamento\b/i),
        feriado: description.match?(/\bferiado|recesso\b/i),
        importante: description.match?(/\bmatrícula|trancamento|data-limite\b/i)
      }
    }
  end
end

class Exporter
  def initialize(events)
    @events = events
  end

  def call(path:)
    format = File.extname(path).delete(".")
    case format
    when "ics"
      export_ical(path)
    when "json"
      export_json(path)
    else
      throw ArgumentError.new("Formato #{format} não suportado")
    end
  end

  private

  def export_ical(path)
    cal = Icalendar::Calendar.new
    cal.prodid = "-//Ariel//Calendário Acadêmico UFMG//pt-BR"
    cal.ip_name = "Calendário Acadêmico UFMG"
    cal.color = "#C8102E" # Marca UFMG
    cal.url = "https://ariel-codes.github.io/calendario-ufmg"
    cal.source = "https://ariel-codes.github.io/calendario-ufmg/Calendario+Academico+UFMG.ics"
    cal.last_modified = Icalendar::Values::DateTime.new(Time.now).value_ical
    cal.refresh_interval = "P1M"

    @events.each do |event|
      cal.event do |e|
        e.dtstart = Icalendar::Values::Date.new(event[:start])
        e.dtend = Icalendar::Values::Date.new(event[:end])
        e.summary = generate_summary(event)
        e.description = event[:title]
        e.ip_class = "PUBLIC"

        if event[:flags][:importante]
          e.alarm do |alarm|
            alarm.action = "DISPLAY"
            alarm.trigger = "-PT6D"
            alarm.description = generate_subject(event)
          end
          e.alarm do |alarm|
            alarm.action = "DISPLAY"
            alarm.trigger = "-PT16H30M"
            alarm.description = "Amanhã na UFMG: #{event[:title]}"
          end
        end
        e.alarm do |alarm|
          alarm.action = "DISPLAY"
          alarm.trigger = DateTime.parse("#{event[:start]}T07:30:00-03:00").to_s
          alarm.description = generate_subject(event)
        end
      end
    end

    cal.publish
    File.write(path, cal.to_ical)
  end

  def export_json(path)
    JSON.dump(@events, File.open(path, "w"))
  end

  def generate_summary(event)
    flags = event[:flags]

    public = if flags[:grad] && flags[:pos]
      "Graduação e Pós-Graduação"
    elsif flags[:grad]
      "Graduação"
    elsif flags[:pos]
      "Pós-Graduação"
    end

    type = if flags[:matricula]
      "Matrícula"
    elsif flags[:trancamento]
      "Trancamento"
    elsif flags[:feriado]
      "Recesso/Feriado"
    else
      "Outros"
    end

    "UFMG: #{public&.+(" -")} #{type}#{flags[:importante] ? "!" : ""}"
  end

  def generate_subject(event)
    date = event[:start].strftime("%d/%m")
    "Alerta #{date} na #{generate_summary(event)}"
  end
end

events = Scraper.new.call(years: Time.now.year..(Time.now.year + 1))
Exporter.new(events).call(path: "website/data/calendario.json")
Exporter.new(events).call(path: "website/public/Calendario+Academico+UFMG.ics")
