import {
    EC2Client,
    DescribeInstancesCommand,
    DescribeVolumesCommand,
    StopInstancesCommand,
    ModifyVolumeAttributeCommand
} from "@aws-sdk/client-ec2";
import { CloudWatchClient, GetMetricStatisticsCommand } from "@aws-sdk/client-cloudwatch";

const nowUtc = () => new Date();
const daysAgo = n => new Date(nowUtc().getTime() - n * 86_400_000);

const getEndOfMonth = d => new Date(Date.UTC(
      d.getUTCFullYear(),
    d.getUTCMonth() + 1,
    1,// first day next mounts…
      0, 0, 0, 0          // …in 00:00 UTC
    ));
const hasZeroMetric = async (cw, namespace, metricName, dimensions, start, end) => {
    const resp = await cw.send(new GetMetricStatisticsCommand({
        Namespace: namespace,
        MetricName: metricName,
        Dimensions: dimensions,
        StartTime: start,
        EndTime: end,
        Period: 86400,
        Statistics: ["Sum"],
    }));
    const pts = resp.Datapoints || [];
    return pts.length === 0 || pts.every(p => p.Sum === 0);
};

const INSTANCE_PRICES = {
    "t3.micro": 0.0104,
    "t3.small": 0.0209,
    "t3.medium": 0.0418,
    "t3.large": 0.0836
};
const estimateInstancePrice = type => INSTANCE_PRICES[type] || 0.05;

export async function handler(event) {
    const regions       = process.env.REGIONS.split(",");
    const idleDays = parseInt(process.env.IDLE_THRESHOLD_DAYS, 10);
    const excludeTags   = new Set((process.env.EXCLUDE_TAGS || "").split(",").filter(x => x));
    const dryRun        = process.env.DRY_RUN === "true";

    const cutoff  = daysAgo(idleDays);
    const endTime = nowUtc();
    const millisInDay = 86_400_000;
    const raw = (getEndOfMonth(endTime) - endTime) / millisInDay;
    const daysLeft = Math.max(1, Math.ceil(raw)); // чтобы всегда был ≥ 1

    // how many days are there in the current month in total
    const daysInMonth = new Date(Date.UTC(endTime.getUTCFullYear(), endTime.getUTCMonth() + 1, 0)).getUTCDate();

    let projectedRemaining = 0;   // by the end of the month
    let projectedFullMonth = 0;   // full calendar month

    for (const region of regions) {
        const ec2 = new EC2Client({ region });
        const cw  = new CloudWatchClient({ region });

        // EC2
        const instResp = await ec2.send(new DescribeInstancesCommand({}));
        for (const res of instResp.Reservations || []) {
            for (const inst of res.Instances || []) {
                const tags = new Set((inst.Tags || []).map(t => t.Key));
                const ageDays = (endTime - new Date(inst.LaunchTime)) / (24*3600*1000);
                if (ageDays < idleDays || [...tags].some(k => excludeTags.has(k))) continue;

                const idle = await hasZeroMetric(
                    cw,
                    "AWS/EC2",
                    "CPUUtilization",
                    [{ Name: "InstanceId", Value: inst.InstanceId }],
                    cutoff,
                    endTime
                );
                if (idle) {
                    console.info(`EC2 ${inst.InstanceId} idle (dryRun=${dryRun})`);
                    if (!dryRun) {
                        await ec2.send(new StopInstancesCommand({InstanceIds: [inst.InstanceId]}));
                    }
                    const hourly = estimateInstancePrice(inst.InstanceType);
                    projectedRemaining += hourly * 24 * daysLeft;
                    projectedFullMonth += hourly * 24 * daysInMonth;
                }
            }
        }

        // EBS
        const volResp = await ec2.send(new DescribeVolumesCommand({Filters: [{ Name: "status", Values: ["available"] }]}));
        for (const vol of volResp.Volumes || []) {
            const tags = new Set((vol.Tags || []).map(t => t.Key));
            const ageDays = (endTime - new Date(vol.CreateTime)) / 86_400_000;

            if (ageDays < idleDays || [...tags].some(k => excludeTags.has(k))) continue;

            const idle = await hasZeroMetric(
                cw,
                "AWS/EBS",
                "VolumeConsumedReadWriteOps",
                [{ Name: "VolumeId", Value: vol.VolumeId }],
                cutoff,
                endTime
            );
            if (idle) {
                console.info(`EBS ${vol.VolumeId} idle (dryRun=${dryRun})`);
                if (!dryRun) {
                    await ec2.send(new ModifyVolumeAttributeCommand({VolumeId: vol.VolumeId, AutoEnableIO: { Value: false }}));
                }
                const monthlyDiskPrice = 0.08 * vol.Size;     // $/mo
                projectedRemaining += monthlyDiskPrice * (daysLeft / daysInMonth);
                projectedFullMonth += monthlyDiskPrice;
            }
        }
    }

    console.info(`Projected (remaining) until the end of the month: $${projectedRemaining.toFixed(2)}`)
    console.info(`full-month: $${projectedFullMonth.toFixed(2)}`);

    return {
        status: "ok",
        projected_remaining: projectedRemaining.toFixed(2),
        projected_full_month: projectedFullMonth.toFixed(2)
    };
}
