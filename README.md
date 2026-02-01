# inference server

```
docker build -t inference-service .
docker tag inference-service darwinche/inference-service:v0.0.22
docker push darwinche/inference-service:v0.0.22
```

# backend server

1. manage a s3 file which is a list of
```
{
    id: "#{hash of image}",
    extracted: {
        name_pinyin:,
        name_cn:,
        birthday:,
        baptism_date:,
    },
    status: "uploaded" => "extracted" => "generated" => "reviewed"
}
```
2. left sidebar shows a list of items, and can upload image, can batch upload
3. has a button to send all unextracted items to inference server, and fill the data one by one
3. the profile shows the name_cn || name_pinyin || id
4. When selected a profile, the page shows
    - original image
    - extracted headshot
    - extracted paper
    - extracted info
    - generated certificate
5. User can regenerate certificate for all, when the template changed