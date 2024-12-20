using TidierVest, Gumbo, Cascadia
using DataFrames, CSV
using ProgressBars
using Base.Iterators

struct GameInfo
    name::String
    country::String
    description::String
    thumbnail::String
    publisher_names::String
    developer_names::String
    platform::String
    steam_link::String
    release_date::String
    genre::String
    epic_link::String
    playstation_link::String
    xbox_link::String
    switch_link::String
end

function broad_in(vec1::Vector,vec2::Vector)
    bit::BitVector = []
    for v in vec1
        push!(bit,v in vec2)
    end
    return bit
end

function extract_platforms(input_string::AbstractString)
    # Define regular expression pattern to match platform names
    regex_pattern = r"Windows|macOS|SteamOS \+ Linux"
    
    # Use eachmatch function to find all occurrences of platform names
    matches = collect(eachmatch(regex_pattern, input_string))
    
    # Extract matched platform names
    platforms = [m.match for m in matches]
    
    return platforms
end

function final_str_platforms(input_string::String)::String
    platforms = extract_platforms(input_string)

    finalstr = ""
    for p in platforms
        finalstr = finalstr*p*", "
    end
    return finalstr[begin:end-2]
end

function get_genre(html)::String
    a = html_elements(html,"div")
    b = html_elements(a,".block_content_inner") 
    c::Vector{String} = html_elements(b, ["span","a"]) |> html_text3
    return join(unique(c), ", ")
end

function get_game_info(url::String,country::String)
    html = read_html(url)

    name = html_elements(html, ".apphub_AppName")[1] |> html_text3
    description = html_elements(html, ".game_description_snippet")[1] |> html_text3
    description = replace(description, "\t" => "")
    if length(description) > 185
        description = description[1:185]*"..."
    end
    developer_names = "Unknown"
    publisher_names = "Unknown"
    try
        developer_names = html_elements(html, ".dev_row")[1].children[2] |> html_text3    
        publisher_names = html_elements(html, ".dev_row")[2].children[2] |> html_text3
    catch
    end
    release_date = (html_elements(html, ".date") |> html_text3)[1]
    thumbnail = html_attrs(html_elements(html, ".game_header_image_full"), "src")[1]
    
    # Hardcoded values
    country = country
    platform = "Windows"
    try
        platform = final_str_platforms((html_elements(html,".sysreq_tabs") |> html_text3)[1])    
    catch
    end

    genre = "Unknown"
    try
        genre= get_genre(html)
    catch
    end
    epic_link = "Unknown"
    playstation_link = "Unknown"
    xbox_link = "Unknown"
    switch_link = "Unknown"
    
    return GameInfo(name, country, description, thumbnail, publisher_names, developer_names, platform, url, release_date,genre,epic_link,playstation_link,xbox_link,switch_link)
end
cleanlink(str) = split(str,"?")[1]

function failed_info(url::String,country::String)
    return GameInfo("failed", country, "failed", "failed", "failed", "failed", "failed", url, "failed","failed","failed","failed","failed","failed")
end

function gameinfo_df(a::GameInfo)::DataFrame
    df = DataFrame(
        Name = [a.name],
        Country = [a.country],
        Description = [a.description],
        Thumbnail = [a.thumbnail],
        Publisher_Names = [a.publisher_names],
        Developer_Names = [a.developer_names],
        Platform = [a.platform],
        Steam_Link = [a.steam_link],
        Release_Date = [a.release_date],
        Genre = [a.genre],
        Epic_Link = [a.epic_link],
        Playstation_Link = [a.playstation_link],
        Xbox_Link = [a.xbox_link],
        Switch_Link = [a.switch_link]
    )
    return df
end

"""
The most important function
Given a dataframe with 2 columns, :country and :url we will scrape the info from steam. 
Will return a dataframe with the added columns
"""
function extract_data(df::DataFrame)::DataFrame
    data::Vector{GameInfo} = []
    print("New entries are from: ")
    println(unique(df[:,:country]))
    for i in ProgressBar(1:nrow(df)) # urls
        try
            push!(data,get_game_info(df[i,:url],df[i,:country]))    
        catch
            push!(data,failed_info(df[i,:url],df[i,:country]))
        end
    end

    df_final::DataFrame = DataFrame()
        for d::GameInfo in data
            df_final = vcat(df_final,gameinfo_df(d))
        end

    return df_final
end

function save_data(df::DataFrame,country::String)
    if !isdir("export")
        mkdir("export")
    end

    bits ::BitVector= df[:,"Name"] .== "failed"

    failed::DataFrame= df[bits,:]
    goods::DataFrame = df[.!bits,:]

    failed = select(failed, :Country, :Steam_Link)

    country_path = "export/"*country*".csv"
    failed_path = "export/failed.csv"
    write_db(country_path,goods)
    write_db(failed_path,failed)

    return nothing
end

function write_db(path::String,df::DataFrame)
    if isfile(path)
        current = CSV.read(path, DataFrame; delim = ";;")
        df = vcat(current,df)
        df = unique(df, :Steam_Link, keep=:last)
    end
    CSV.write(path,df, delim =";;")
    return nothing
end

## Checks current .csvs and it will return a new DF without the urls that we already have.
function clean_ifexists(df::DataFrame;in_failed::Bool=false)::DataFrame
    unique_countries::Vector{String} = unique(df[:,:country])
    return_df::DataFrame = DataFrame()
    for unique_country in unique_countries
        if in_failed
            path = "export/failed.csv"
        else
            path = "export/"*unique_country*".csv"
        end
        sliced_df::DataFrame = df[df[:,:country] .== unique_country,:]
        if (isfile(path))
            available_df = CSV.read(path, DataFrame, stringtype=String; delim = ";;")
            list_urls::Vector{String} = available_df[:,:Steam_Link]
            bit::BitVector = []
            for i in (1:nrow(sliced_df))
                push!(bit,sliced_df[i,:url] ∉ list_urls)
            end
            return_df = vcat(return_df,sliced_df[bit,:])
        else 
            create_empty_csv(path)
            return_df = vcat(return_df,sliced_df)
        end
    end
    return return_df
end

function create_empty_csv(path::String)
    columns = [
    "Name", "Country", "Description", "Thumbnail", "Publisher_Names",
    "Developer_Names", "Platform", "Steam_Link", "Release_Date", "Genre",
    "Epic_Link", "Playstation_Link", "Xbox_Link", "Switch_Link"
    ]

    df = DataFrame([[] for _ in columns], columns)
    CSV.write(path, df, delim=";;")
    return nothing
end