defmodule BaptismBackend.Certificate do
  @moduledoc """
  Module for generating baptism certificates.
  """

  alias BaptismBackend.S3Storage
  alias BaptismBackend.Struct.Profile

  require Logger

  @work_dir "/tmp/python-script"
  @template_path Path.join(@work_dir, "template.pptx")

  @doc """
  Generates a baptism certificate for the given profile data.
  """

  def generate_certificate(%Profile{} = profile, config) do
    with :ok <- ensure_directory(),
         :ok <- maybe_fetch_template(),
         :ok <- fetch_headshot(profile.id),
         :ok <- python_generate_pptx(profile, config),
         :ok <- generate_pptx_preview(profile.id),
         :ok <- upload_pptx(profile.id),
         :ok <- upload_pptx_preview(profile.id) do
      cleanup_files(profile.id)
      Logger.info("Successfully generated certificate for profile #{profile.id}")
      :ok
    else
      error ->
        Logger.error("Failed to generate certificate for profile #{profile.id}: #{inspect(error)}")
        cleanup_files(profile.id)
        error
    end
  end

  defp maybe_fetch_template do
    S3Storage.download_template(@template_path)
  end

  defp ensure_directory do
    Logger.info("Ensuring working directory #{@work_dir} exists")
    with :ok <- File.mkdir_p(@work_dir),
         :ok <- copy_python_script() do
      :ok
    end
  end

  defp copy_python_script do
    Logger.info("Copying python script to #{@work_dir}")

    # In production (Docker), python folder is at /app/python
    # In dev, it's relative to priv_dir
    source = if File.exists?("/app/python/script.py") do
      "/app/python/script.py"
    else
      Path.join(:code.priv_dir(:baptism_backend), "../python/script.py")
    end

    dest = Path.join(@work_dir, "script.py")

    # Always copy to ensure we have the latest version
    case File.cp(source, dest) do
      :ok -> :ok
      {:error, reason} -> {:error, {:copy_script_failed, reason}}
    end
  end

  defp fetch_headshot(id) do
    Logger.info("Fetching headshot for profile #{id}")
    local_path = Path.join(@work_dir, "headshot_#{id}.jpg")
    S3Storage.download_headshot(id, local_path)
  end

  defp upload_pptx(id) do
    Logger.info("Uploading PPTX for profile #{id}")
    local_path = Path.join(@work_dir, "output_#{id}.pptx")
    S3Storage.upload_file("certificates/#{id}.pptx", local_path)
  end

  defp upload_pptx_preview(id) do
    Logger.info("Uploading PDF preview for profile #{id}")
    local_path = Path.join(@work_dir, "output_#{id}.pdf")
    S3Storage.upload_pdf_preview("certificate_previews/#{id}.pdf", local_path)
  end

  defp cleanup_files(id) do
    File.rm(Path.join(@work_dir, "headshot_#{id}.jpg"))
    File.rm(Path.join(@work_dir, "output_#{id}.pptx"))
    File.rm(Path.join(@work_dir, "output_#{id}.pdf"))
  end

  defp generate_pptx_preview(id) do
    output_path = Path.join(@work_dir, "output_#{id}.pptx")
    Logger.info("Generating PDF preview for #{id}")
    case System.cmd("soffice", ["--headless", "--convert-to", "pdf", output_path], cd: @work_dir) do
      {_output, 0} -> :ok
      {error, _code} -> {:error, {:soffice_failed, error}}
    end
  end

  defp python_generate_pptx(profile, config) do
    Logger.info("Generating PPTX for profile #{profile.id}")
    input = build_pptx_input(profile, config)
    script_path = Path.join(@work_dir, "script.py")
    input_file = Path.join(@work_dir, "input_#{profile.id}.txt")

    # Write input to file
    case File.write(input_file, input) do
      :ok ->
        Logger.info("Running python script for profile #{profile.id}")
        result = System.cmd("python3", [script_path, input_file],
          cd: @work_dir,
          stderr_to_stdout: true
        )
        Logger.info("Python script output for profile #{profile.id}: #{elem(result, 0)}")

        # Clean up input file
        File.rm(input_file)

        case result do
          {_output, 0} -> :ok
          {error, _code} -> {:error, {:python_script_failed, error}}
        end

      {:error, reason} ->
        {:error, {:write_input_failed, reason}}
    end
  end

  defp build_pptx_input(profile, config) do
    headshot_config = Map.get(config, "headshot", "left=5 top=1 w=3")
    name_config = Map.get(config, "name", "left=1 top=1 w=6 h=1.5 fontsz=18")
    birthday_config = Map.get(config, "birthday", "left=1 top=2.5 w=6 h=1.5 fontsz=18 font=\"Times New Roman\"")
    bap_day_config = Map.get(config, "baptism_day", "left=1 top=4 w=6 h=1.5 fontsz=18 font=\"Times New Roman\"")
    bap_month_config = Map.get(config, "baptism_month", "left=2 top=4 w=6 h=1.5 fontsz=18 font=\"Times New Roman\"")
    bap_year_config = Map.get(config, "baptism_year", "left=3 top=4 w=6 h=1.5 fontsz=18 font=\"Times New Roman\"")
    sign_date_config = Map.get(config, "sign_date", "left=1 top=5.5 w=6 h=1.5 fontsz=18 font=\"Times New Roman\"")
    sign_date_value = Map.get(config, "sign_date_value", Date.to_string(Date.utc_today()))

    # Parse sign_date_value to Date if it's a string
    sign_date = case Date.from_iso8601(sign_date_value) do
      {:ok, date} -> date
      _ -> Date.utc_today()
    end

    """
    template.pptx output_#{profile.id}.pptx
    img headshot_#{profile.id}.jpg
    #{headshot_config}
    txt #{profile.name_pinyin} #{profile.name_cn}
    #{name_config} align=left
    txt #{format_date(profile.birthday)}
    #{birthday_config} align=left
    txt #{format_day(profile.baptism_date)}
    #{bap_day_config} align=left
    txt #{format_month(profile.baptism_date)}
    #{bap_month_config} align=left
    txt #{format_year(profile.baptism_date)}
    #{bap_year_config} align=left
    txt #{format_date(sign_date)}
    #{sign_date_config} align=left
    """
  end

  defp format_day(nil), do: ""
  defp format_day(%Date{} = date), do: Calendar.strftime(date, "%d")

  defp format_month(nil), do: ""
  defp format_month(%Date{} = date), do: Calendar.strftime(date, "%B")

  defp format_year(nil), do: ""
  defp format_year(%Date{} = date), do: Calendar.strftime(date, "%Y")

  defp format_date(nil), do: ""
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%B %d, %Y")

  @doc """
  Combines multiple certificates into a single PPTX file.
  Returns {:ok, pptx_binary} or {:error, reason}.
  """
  def combine_certificates(profile_ids) do
    tmp_dir = "/tmp/combine_certs_#{length(profile_ids)}_#{System.unique_integer([:positive])}"
    File.mkdir_p!(tmp_dir)

    try do
      # Download all certificates to temp files
      input_files =
        profile_ids
        |> Enum.with_index()
        |> Enum.map(fn {profile_id, idx} ->
          case S3Storage.download_certificate(profile_id) do
            {:ok, content} ->
              input_path = Path.join(tmp_dir, "input_#{idx}.pptx")
              File.write!(input_path, content)
              input_path

            {:error, reason} ->
              Logger.error("Failed to download certificate #{profile_id}: #{inspect(reason)}")
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      if Enum.empty?(input_files) do
        {:error, "No certificates could be downloaded"}
      else
        # Run Python script to combine PPTX files
        output_path = Path.join(tmp_dir, "combined.pptx")
        python_script = find_python_script("combine_pptx.py")

        args = [python_script, output_path | input_files]

        case System.cmd("python3", args, stderr_to_stdout: true) do
          {output, 0} ->
            Logger.info("Combined PPTX: #{output}")
            pptx_binary = File.read!(output_path)
            {:ok, pptx_binary}

          {error_output, exit_code} ->
            Logger.error("Failed to combine PPTX files (exit code #{exit_code}): #{error_output}")
            {:error, "Failed to combine certificates: #{error_output}"}
        end
      end
    after
      # Clean up temp files
      File.rm_rf(tmp_dir)
    end
  end

  defp find_python_script(script_name) do
    # In production (Docker), python folder is at /app/python
    # In dev, it's relative to priv_dir
    if File.exists?("/app/python/#{script_name}") do
      "/app/python/#{script_name}"
    else
      Path.join(:code.priv_dir(:baptism_backend), "../python/#{script_name}")
    end
  end
end
