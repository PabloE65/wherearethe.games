using PyCall
using TidierVest, Gumbo, DataFrames
include("scraper.jl")

PyCall.py"""
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.keys import Keys
import time

def scroll_and_get_html(url):
    # Set up the webdriver (you'll need to specify the path to your webdriver)
    driver = webdriver.Chrome()
    
    # Open the website
    driver.get(url)
    
    # Get the initial height of the page
    last_height = driver.execute_script("return document.body.scrollHeight")
    
    while True:
        # Scroll to the bottom of the page
        driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
        
        # Wait for the page to load
        time.sleep(2)
        
        # Calculate new scroll height and compare with last scroll height
        new_height = driver.execute_script("return document.body.scrollHeight")
        if new_height == last_height:
            break
        last_height = new_height
    
    # Get the page source (HTML)
    html = driver.page_source
    
    # Close the browser
    driver.quit()
    
    return html
"""

scroll_and_get_html(str) = py"scroll_and_get_html"(str)
chopchop(data) = split(data,"?curator")[1]

function check_slash(str)
    if last(str) == '/'
        return str 
    else 
        str*"/"
    end
end

## list
function create_df1(url::String,country::String)::DataFrame
    html = scroll_and_get_html(url) |> parsehtml
    d = html_elements(html,[".MY9Lke1NKqCw4L796pl4u",".Focusable","a"])
    data::Vector{String} = html_attrs(d,"href") |> unique .|> chopchop .|> check_slash
    return DataFrame(country = country, url = data)
end

## #browse
function create_df2(url::String,country::String,get_desc::Bool=false)::DataFrame
    html = scroll_and_get_html(url) |> parsehtml
    b = html_elements(html,".recommendation_link") ## all the recomendations of a mentor
    listgames::Vector{String} = html_attrs(b,"href") .|> cleanlink |> unique .|> check_slash
    description = html_elements(html,".recommendation_desc")
    if get_desc
        return DataFrame(url = listgames, country = country,description=description)
    else
        return DataFrame(url = listgames, country = country)
    end
end

function create_df(url::String,country::String,get_desc::Bool=false)::DataFrame
    is_curator = last(split(url,"/")) == "#browse"
    is_list = occursin("list",url) 
    
    if is_curator
        return create_df2(url,country,get_desc)
    elseif is_list
        return create_df1(url,country)
    else 
        throw("Invalid URL: "*url)
    end
end

function process_df(dataframe::DataFrame)
    dataframe = unique(dataframe,:url) # remove repetitions
    dataframe = clean_ifexists(dataframe) # checks that we don't have it already in the database
    dataframe = clean_ifexists(dataframe;in_failed=true) # checks that we don't have it already in the database
    
    if nrow(dataframe) > 0
        dataframe = extract_data(dataframe)
        unique_countries::Vector{String} = unique(dataframe[:,:Country])

        for unique_country in unique_countries
            sliced_dataframe::DataFrame = dataframe[dataframe[:,:Country] .== unique_country,:]
            save_data(sliced_dataframe,unique_country)
        end
    else 
        println("No new data")
    end
    return nothing
end
