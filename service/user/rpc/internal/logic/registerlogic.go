package logic

import (
	"context"

	"mall/common/cryptx"
	"mall/service/user/model"
	"mall/service/user/rpc/internal/svc"
	"mall/service/user/rpc/types/user"

	"github.com/zeromicro/go-zero/core/logx"
	"google.golang.org/grpc/status"
)

type RegisterLogic struct {
	ctx    context.Context
	svcCtx *svc.ServiceContext
	logx.Logger
}

func NewRegisterLogic(ctx context.Context, svcCtx *svc.ServiceContext) *RegisterLogic {
	return &RegisterLogic{
		ctx:    ctx,
		svcCtx: svcCtx,
		Logger: logx.WithContext(ctx),
	}
}

func (l *RegisterLogic) Register(in *user.RegisterRequest) (*user.RegisterResponse, error) {
	// 1. 前置参数校验
	if in.Mobile == "" || in.Password == "" {
		return nil, status.Error(400, "手机号和密码不能为空")
	}

	// 2. 校验手机号是否已注册
	_, err := l.svcCtx.UserModel.FindOneByMobile(l.ctx, in.Mobile)
	if err == nil {
		return nil, status.Error(100, "该用户已存在")
	}

	// 3. 手机号不存在，执行注册
	if err == model.ErrNotFound {
		newUser := model.User{
			Name:     in.Name,
			Gender:   uint64(in.Gender),
			Mobile:   in.Mobile,
			Password: cryptx.PasswordEncrypt(l.svcCtx.Config.Salt, in.Password),
		}

		res, err := l.svcCtx.UserModel.Insert(l.ctx, &newUser)
		if err != nil {
			return nil, status.Error(500, "注册失败，请稍后重试")
		}

		t, err := res.LastInsertId()
		newUser.Id = uint64(t)
		if err != nil {
			return nil, status.Error(500, "获取用户信息失败")
		}

		return &user.RegisterResponse{
			Id:     int64(newUser.Id),
			Name:   newUser.Name,
			Gender: int64(newUser.Gender),
			Mobile: newUser.Mobile,
		}, nil
	}

	// 4. 兜底：数据库/网络等未知异常
	return nil, status.Error(500, "服务异常，请稍后重试")
}
