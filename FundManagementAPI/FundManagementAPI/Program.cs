using System.Security.Claims;
using System.Globalization;
using FundManagementAPI.Data;
using FundManagementAPI.Repositories;
using FundManagementAPI.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Logging.ClearProviders();
builder.Logging.AddConsole();
builder.Logging.AddDebug();

// Add services to the container.

builder.Services.AddControllers();
builder.Services.AddDataProtection();
builder.Services.AddScoped<ISqlDataAccess, SqlDataAccess>();
builder.Services.AddScoped<ICashAdvanceRepository, CashAdvanceRepository>();
builder.Services.AddScoped<RfpRepository>();
builder.Services.AddScoped<RequestPrintService>();
builder.Services.AddScoped<FineReportSignInService>();
builder.Services.AddScoped<RfpAttachmentService>();
builder.Services.AddHostedService<FineReportAttachmentImportWorker>();
builder.Services.AddCors(options =>
{
    options.AddPolicy("ReactClient", policy =>
    {
        policy
            .WithOrigins("http://localhost:5173", "https://localhost:5173", "https://fms.cathaylandinc.com")
            .AllowAnyHeader()
            .AllowAnyMethod()
            .AllowCredentials();
    });
});
// Learn more about configuring Swagger/OpenAPI at https://aka.ms/aspnetcore/swashbuckle
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();

app.UseCors("ReactClient");

app.Use(async (context, next) =>
{
    if (!context.Request.Path.StartsWithSegments("/api"))
    {
        await next(context);
        return;
    }
    context.Response.Headers.CacheControl = "no-store";
    var signIn = context.RequestServices.GetRequiredService<FineReportSignInService>();
    var user = await signIn.GetUserAsync(context.Request.Cookies["FMS_id"], context.RequestAborted);
    if (user is null)
    {
        app.Logger.LogWarning("FMS access denied: {Reason}; host {Host}; path {Path}",
            context.Request.Cookies.ContainsKey("FMS_id") ? "cookie did not match an active FMS account" : "FMS_id cookie missing",
            context.Request.Host, context.Request.Path);
        context.Response.StatusCode = StatusCodes.Status404NotFound;
        return;
    }
    var userId = user.UserId.ToString(CultureInfo.InvariantCulture);
    context.User = new ClaimsPrincipal(new ClaimsIdentity(
        [new Claim(ClaimTypes.NameIdentifier, userId)], "FineReportCookie"));
    context.Items["FmsUser"] = user;
    app.Logger.LogInformation("Authenticated FMS user {UserId}: {Method} {Path}",
        userId, context.Request.Method, context.Request.Path);
    await next(context);
});

app.UseAuthorization();

app.MapControllers();

app.Run();
